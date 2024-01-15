USE DATABASE CONTAINERS_DB;
USE SCHEMA CONTAINERS_DB.SIMPLE_WIKI_SEARCH;
USE WAREHOUSE SIMPLE_WIKI_WH;

CREATE STAGE IF NOT EXISTS specs ENCRYPTION = (TYPE='SNOWFLAKE_SSE');
CREATE STAGE IF NOT EXISTS models ENCRYPTION = (TYPE='SNOWFLAKE_SSE');

CREATE IMAGE REPOSITORY IF NOT EXISTS images;
SHOW IMAGE REPOSITORIES IN SCHEMA CONTAINERS_DB.SIMPLE_WIKI_SEARCH;

DESCRIBE COMPUTE POOL SIMPLE_WIKI_POOL_XS;
-- ALTER COMPUTE POOL SIMPLE_WIKI_POOL_XS SUSPEND;
-- ALTER COMPUTE POOL SIMPLE_WIKI_POOL_XS RESUME;
DESCRIBE COMPUTE POOL SIMPLE_WIKI_POOL_GPU_S;
-- ALTER COMPUTE POOL SIMPLE_WIKI_POOL_GPU_S SUSPEND;
-- ALTER COMPUTE POOL SIMPLE_WIKI_POOL_GPU_S RESUME;

DESCRIBE COMPUTE POOL SIMPLE_WIKI_POOL_GPU_M;
-- ALTER COMPUTE POOL SIMPLE_WIKI_POOL_GPU_M SUSPEND;
-- ALTER COMPUTE POOL SIMPLE_WIKI_POOL_GPU_M RESUME;

//--//--//--//--//--//--//--//--//--//--//--//--//--//--//--//--//--//--//
// ONE GPU
DROP SERVICE IF EXISTS CONTAINERS_DB.SIMPLE_WIKI_SEARCH.SIMPLE_WIKI_FASTAPI_SERVICE_ONE_GPU;
create service CONTAINERS_DB.SIMPLE_WIKI_SEARCH.SIMPLE_WIKI_FASTAPI_SERVICE_ONE_GPU
in compute pool SIMPLE_WIKI_POOL_GPU_S
from @specs
spec='simple-wiki-fastapi-service_one-gpu.yml'
EXTERNAL_ACCESS_INTEGRATIONS = (HUGGING_FACE_ACCESS_INTEGRATION)
;

show services in schema CONTAINERS_DB.SIMPLE_WIKI_SEARCH;
DESCRIBE SERVICE CONTAINERS_DB.SIMPLE_WIKI_SEARCH.SIMPLE_WIKI_FASTAPI_SERVICE_ONE_GPU;

CALL SYSTEM$GET_SERVICE_STATUS('CONTAINERS_DB.SIMPLE_WIKI_SEARCH.SIMPLE_WIKI_FASTAPI_SERVICE_ONE_GPU');
CALL SYSTEM$GET_SERVICE_LOGS('CONTAINERS_DB.SIMPLE_WIKI_SEARCH.SIMPLE_WIKI_FASTAPI_SERVICE_ONE_GPU', '0', 'simple-wiki-fastapi-service-one-gpu', 10);

ALTER SERVICE CONTAINERS_DB.SIMPLE_WIKI_SEARCH.SIMPLE_WIKI_FASTAPI_SERVICE_ONE_GPU SUSPEND ;
ALTER SERVICE CONTAINERS_DB.SIMPLE_WIKI_SEARCH.SIMPLE_WIKI_FASTAPI_SERVICE_ONE_GPU RESUME ;

//--//--//--//--//--//--//--//--//--//--//--//--//--//--//--//--//--//--//

CREATE OR REPLACE FUNCTION fastapi_embed_one_gpu(input STRING)
RETURNS STRING
SERVICE=SIMPLE_WIKI_FASTAPI_SERVICE_ONE_GPU      // Snowflake container service
ENDPOINT='simple-wiki-fastapi-service-one-gpu'   // The endpoint within the container
MAX_BATCH_ROWS=32                                // limit the size of the batch
AS '/embed';                                     // The API endpoint
-- DROP FUNCTION fastapi_embed_one_gpu(STRING);

select fastapi_embed_one_gpu('a') as a;


CREATE OR REPLACE FUNCTION fastapi_search_one_gpu(input STRING)
RETURNS STRING
SERVICE=SIMPLE_WIKI_FASTAPI_SERVICE_ONE_GPU      // Snowflake container service
ENDPOINT='simple-wiki-fastapi-service-one-gpu'   // The endpoint within the container
MAX_BATCH_ROWS=32                                // limit the size of the batch
AS '/search';                                    // The API endpoint
-- DROP FUNCTION fastapi_search_one_gpu;

select
      response.value:corpus_id::NUMBER(15,0) as corpus_id
    , response.value:score::NUMBER(30, 25) as score
from LATERAL
    FLATTEN(
        PARSE_JSON(
            fastapi_search_one_gpu(
                'What is the capital of France?'
            )
        )::VARIANT
    ) as response
;



CREATE OR REPLACE FILE FORMAT simple_wiki_json_format
    TYPE = 'JSON'
    STRIP_OUTER_ARRAY = TRUE
;

with _PASSAGES as (
    select
          $1:corpus_id::NUMBER(15,0) as corpus_id
        , $1:corpus_title::VARCHAR as corpus_title
        , $1:corpus_text::VARCHAR as corpus_text
    FROM @data/workdir/passages-2020-11-01.json.gz
        (FILE_FORMAT => 'simple_wiki_json_format')
),
_MATCHING_DOCUMENTS AS (
    select
          response.value:corpus_id::NUMBER(15,0) as corpus_id
        , response.value:score::NUMBER(30, 25) as score
    from LATERAL FLATTEN(
        PARSE_JSON(
            fastapi_search_one_gpu(
                'What is the capital of France?'
            )
        )::VARIANT
    ) as response
)
SELECT p.corpus_id, p.corpus_title, p.corpus_text, d.score
FROM _PASSAGES as p INNER JOIN _MATCHING_DOCUMENTS as d
ON (d.corpus_id = p.corpus_id)
order by score desc
;



SELECT question
FROM VALUES
    ('What is the best orchestra in the world?'),
    ('Number countries Europe'),
    ('When did the cold war end?'),
    ('How long do cats live?'),
    ('How many people live in Toronto?'),
    ('Oldest US president'),
    ('Coldest place earth'),
    ('When was Barack Obama born?'),
    ('Paris eiffel tower'),
    ('Which US president was killed?'),
    ('When is Chinese New Year'),
    ('what is the name of manchester united stadium'),
    ('who wrote cant get you out of my head lyrics'),
    ('where does the story the great gatsby take place'),
    ('who turned out to be the mother on how i met your mother') AS t(question)
;



with _PASSAGES as (
    select
          $1:corpus_id::NUMBER(15,0) as corpus_id
        , $1:corpus_title::VARCHAR as corpus_title
        , $1:corpus_text::VARCHAR as corpus_text
    FROM @data/workdir/passages-2020-11-01.json.gz
        (FILE_FORMAT => 'simple_wiki_json_format')
),
_QUESTIONS AS (
    SELECT question
    FROM VALUES
        ('What is the best orchestra in the world?'),
        ('Number countries Europe'),
        ('When did the cold war end?'),
        ('How long do cats live?'),
        ('How many people live in Toronto?'),
        ('Oldest US president'),
        ('Coldest place earth'),
        ('When was Barack Obama born?'),
        ('Paris eiffel tower'),
        ('Which US president was killed?'),
        ('When is Chinese New Year'),
        ('what is the name of manchester united stadium'),
        ('who wrote cant get you out of my head lyrics'),
        ('where does the story the great gatsby take place'),
        ('who turned out to be the mother on how i met your mother') AS t(question)
),
_MATCHING_DOCUMENTS AS (
    select
          response.value:corpus_id::NUMBER(15,0) as corpus_id
        , response.value:score::NUMBER(30, 25) as score
        , _QUESTIONS.question as question
    from _QUESTIONS, LATERAL FLATTEN(
        PARSE_JSON(fastapi_search_one_gpu(question))::VARIANT
    ) as response
)
SELECT p.corpus_id, p.corpus_title, p.corpus_text, d.score, d.question
FROM _PASSAGES as p INNER JOIN _MATCHING_DOCUMENTS as d
ON (d.corpus_id = p.corpus_id)
order by question, score desc
;
