
-- handler function
CREATE FUNCTION plproxy_call_handler ()
RETURNS language_handler AS '$libdir/plproxy' LANGUAGE C;

-- language
CREATE LANGUAGE plproxy HANDLER plproxy_call_handler;

-- validator function
CREATE FUNCTION plproxy_fdw_validator (text[], oid)
RETURNS boolean AS '$libdir/plproxy' LANGUAGE C;

-- foreign data wrapper
CREATE FOREIGN DATA WRAPPER plproxy VALIDATOR plproxy_fdw_validator;

