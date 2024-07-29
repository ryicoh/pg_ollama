# pg_ollama

`pg_ollamaa` is a [Ollama](https://github.com/ollama/ollama) client for PostgreSQL.

# Usage

```sql
CREATE EXTENSION IF NOT EXISTS http;

CREATE EXTENSION IF NOT EXISTS ollama;

SELECT ollama_insert_default_settings();

SELECT prompt, ollama(prompt) as "answer"
FROM (
  VALUES
    ('What color is a apple?'),
    ('What color is a banana?')
) as q(prompt)

-- prompt                 |answer                                                                                                 |
-- -----------------------+-------------------------------------------------------------------------------------------------------+
-- What color is a apple? |"An apple is typically a reddish-orange fruit. It is a common fruit in many cultures around the world."|
-- What color is a banana?|"A banana is a yellow fruit. It is often used in cooking and baking."                                  |
```
