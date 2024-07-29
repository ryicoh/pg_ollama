CREATE SCHEMA IF NOT EXISTS ollama;

CREATE TABLE ollama.models (
  model VARCHAR(255) PRIMARY KEY, -- gemma:2b
  created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE ollama.endpoints (
  id SERIAL PRIMARY KEY,
  name VARCHAR(255) NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  url VARCHAR(2048) NOT NULL
);

CREATE TABLE ollama.settings (
  id SERIAL PRIMARY KEY,
  name VARCHAR(255) NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  is_default BOOLEAN NOT NULL DEFAULT false,
  model VARCHAR(255) NOT NULL REFERENCES ollama.models (model) ON DELETE CASCADE,
  endpoint_id INTEGER NOT NULL REFERENCES ollama.endpoints (id) ON DELETE CASCADE,
  timeout INTEGER NOT NULL DEFAULT 60
);

CREATE UNIQUE INDEX settings_is_default ON ollama.settings (is_default)
WHERE
  is_default;

CREATE TYPE ollama.message_role AS ENUM('system', 'user', 'assistant', 'tool');

CREATE TABLE ollama.setting_messages (
  setting_id INTEGER NOT NULL REFERENCES ollama.settings (id) ON DELETE CASCADE,
  position INTEGER NOT NULL,
  "role" ollama.message_role NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  content TEXT NOT NULL,
  PRIMARY KEY (setting_id, position),
  CHECK (position >= 1)
);

CREATE TABLE ollama.logs (
  id SERIAL PRIMARY KEY,
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  settings_id INTEGER NOT NULL REFERENCES ollama.settings (id) ON DELETE CASCADE,
  input TEXT NOT NULL,
  request_data JSONB NOT NULL,
  finished_at TIMESTAMP,
  status INTEGER,
  response_data JSONB,
  output TEXT
);

CREATE
OR REPLACE FUNCTION public.ollama (arg_setting_id INTEGER, input text) RETURNS text AS $$
  DECLARE
    var_setting ollama.settings;
    var_endpoint ollama.endpoints;
    var_request_data jsonb;
    var_response public.http_response;
    var_response_data jsonb;
    var_log_id INTEGER;
  BEGIN
    SELECT * INTO var_setting FROM ollama.settings WHERE id = arg_setting_id;
    IF var_setting IS NULL THEN
      RAISE EXCEPTION 'setting not found';
    END IF;

    SELECT * INTO var_endpoint FROM ollama.endpoints WHERE endpoints.id = var_setting.endpoint_id;
    IF var_endpoint IS NULL THEN
      RAISE EXCEPTION 'endpoint not found';
    END IF;

    SELECT 
      jsonb_build_object(
        'model', var_setting.model,
        'stream', false,
        'messages', JSONB_AGG(messages)
      ) INTO var_request_data
    FROM (
      (
        SELECT
          "role"::text,
          content
          FROM ollama.setting_messages WHERE setting_messages.setting_id = arg_setting_id
          ORDER BY position ASC
      )
      UNION ALL
      SELECT 'user', input AS "content"
    ) AS messages;

    INSERT INTO ollama.logs (settings_id, input, request_data)
    VALUES (arg_setting_id, input, var_request_data)
    RETURNING id INTO var_log_id;

    PERFORM http_set_curlopt('CURLOPT_TIMEOUT', var_setting.timeout::text);

    SELECT * INTO var_response
    FROM http_post(
      var_endpoint.url || '/api/chat',
      var_request_data::text,
      'application/json'
    );

    SELECT var_response.content::json INTO var_response_data;

    UPDATE ollama.logs
    SET
      status = var_response.status,
      response_data = var_response_data,
      output = var_response_data->'message'->'content',
      finished_at = CLOCK_TIMESTAMP()
    WHERE id = var_log_id;

    RETURN var_response_data->'message'->'content';
  END
  $$ LANGUAGE plpgsql;

CREATE
OR REPLACE FUNCTION public.ollama (input text) RETURNS text AS $$
  DECLARE
    setting ollama.settings;
    output text;
  BEGIN
    SELECT * INTO setting FROM ollama.settings WHERE is_default = true;
    IF setting IS NULL THEN
      RAISE EXCEPTION 'no enabled settings';
    END IF;

    SELECT public.ollama(setting.id, input) INTO output;
    RETURN output;
  END
  $$ LANGUAGE plpgsql;

CREATE
OR REPLACE FUNCTION public.ollama_insert_default_settings () RETURNS VOID AS $$
  DECLARE
    var_endpoint_id INTEGER;
    var_model VARCHAR(255);
    var_setting_id INTEGER;
  BEGIN
    INSERT INTO ollama.endpoints (name, url)
    VALUES ('default', 'http://localhost:11434')
    RETURNING id INTO var_endpoint_id;

    INSERT INTO ollama.models (model)
    VALUES ('gemma:2b')
    RETURNING model INTO var_model;

    INSERT INTO ollama.settings (name, model, endpoint_id, is_default)
    VALUES ('default', var_model, var_endpoint_id, (SELECT NOT EXISTS (SELECT 1 FROM ollama.settings WHERE is_default = true)))
    RETURNING id INTO var_setting_id;

    INSERT INTO ollama.setting_messages (setting_id, position, "role", content)
    VALUES (var_setting_id, 1, 'system', 'You are a helpful assistant.');
  END
  $$ LANGUAGE plpgsql;
