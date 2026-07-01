DO
$$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'dai_assistant') THEN
        CREATE USER dai_assistant WITH
            NOSUPERUSER
            NOCREATEDB
            NOCREATEROLE
            ENCRYPTED PASSWORD 'dai_assistant';
    END IF;

    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'dai_llm') THEN
        CREATE USER dai_llm WITH
            NOSUPERUSER
            NOCREATEDB
            NOCREATEROLE
            ENCRYPTED PASSWORD 'dai_llm';
    END IF;
END
$$;
