DO
$$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'xlrelease') THEN
        CREATE USER xlrelease WITH
            NOSUPERUSER
            NOCREATEDB
            NOCREATEROLE
            ENCRYPTED PASSWORD 'xlrelease';
    END IF;

    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'xlarchive') THEN
        CREATE USER xlarchive WITH
            NOSUPERUSER
            NOCREATEDB
            NOCREATEROLE
            ENCRYPTED PASSWORD 'xlarchive';
    END IF;
END
$$;
