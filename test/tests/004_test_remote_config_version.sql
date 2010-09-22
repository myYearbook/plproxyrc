CREATE FUNCTION
plproxy.test_remote_config_version()
RETURNS SETOF TEXT
LANGUAGE PLPGSQL AS $body$
DECLARE
  v_major_version plproxy.remote_config_versions.major_version%TYPE;
  v_minor_version plproxy.remote_config_versions.minor_version%TYPE;
  v_patch_version plproxy.remote_config_versions.patch_version%TYPE;
  v_version_qualifier plproxy.remote_config_versions.version_qualifier%TYPE;
BEGIN
  DELETE FROM plproxy.remote_config_versions;
  RETURN NEXT ok(NOT EXISTS(SELECT TRUE FROM plproxy.remote_config_versions),
                 'have no rows in remote_config_versions');
  v_major_version := 0;
  v_minor_version := 1;
  v_patch_version := 0;
  v_version_qualifier := '';
  RETURN NEXT ok(plproxy.new_remote_config_version(v_major_version, 
                                                   v_minor_version, 
                                                   v_patch_version, 
                                                   v_version_qualifier),
                 'new_remote_config_version returned TRUE upon initial version');
  RETURN NEXT is(plproxy.remote_config_version_string(),
                 CAST('0.1.0' AS TEXT), 
                 'have expected current version string.');

  v_major_version := 1;
  v_minor_version := 2;
  v_patch_version := 3;
  v_version_qualifier := 'DEV';
  RETURN NEXT ok(plproxy.new_remote_config_version(v_major_version, 
                                                   v_minor_version, 
                                                   v_patch_version, 
                                                   v_version_qualifier),
                 'new_remote_config_version returned TRUE when updating version.');
  RETURN NEXT is(plproxy.remote_config_version_string(),
                 CAST('1.2.3DEV' AS TEXT), 
                 'have expected current version string.');

  RETURN NEXT throws_ok('SELECT plproxy.new_remote_config_version('
                          || array_to_string(ARRAY[quote_literal(v_major_version),
                                                   quote_literal(v_minor_version),
                                                   quote_literal(v_patch_version),
                                                   quote_literal(v_version_qualifier)],
                                             ', ') || ')',
    '23505', 
    'duplicate key value violates unique constraint "remote_config_versions_key"',
    'cannot insert dupe version');

  RETURN NEXT throws_ok('INSERT INTO plproxy.remote_config_versions'
                        || ' (major_version, minor_version, patch_version, version_qualifier)'
                        || ' VALUES (5, 6, 7, '''')',
    '23505', 
    'duplicate key value violates unique constraint "remote_config_versions_current_key"',
    'cannot insert second current version');
  RETURN;
END
$body$;
