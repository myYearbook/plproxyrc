BEGIN;

CREATE SCHEMA plproxy;
GRANT USAGE ON SCHEMA plproxy TO public;

CREATE FUNCTION plproxy.get_cluster_version(in_cluster text)
RETURNS integer
IMMUTABLE
LANGUAGE SQL AS $_$
  SELECT 1;
$_$;

CREATE FUNCTION
plproxy.get_cluster_config(in_cluster text, OUT key text, OUT val text)
RETURNS SETOF record
LANGUAGE SQL AS $$
  VALUES (CAST('connection_lifetime' AS TEXT), CAST(30 * 60 AS TEXT)),
         ('query_timeout', '30');
$$;

CREATE FUNCTION plproxy.get_cluster_partitions(in_cluster text)
RETURNS SETOF text
STRICT
LANGUAGE PLPGSQL AS $_$
BEGIN
  IF in_cluster = 'new-cluster' THEN
    RETURN NEXT 'new-cluster-partition-1';
    RETURN NEXT 'new-cluster-partition-2';
  ELSIF in_cluster = 'new-cluster-2' THEN
    RETURN NEXT 'new-cluster-2-partition-1';
    RETURN NEXT 'new-cluster-2-partition-2';
  ELSE
    RAISE EXCEPTION 'Unknown cluster %', quote_literal(in_cluster);
  END IF;
  RETURN;
END;
$_$;

COMMIT;