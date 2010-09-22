BEGIN;
SELECT plproxy.new_cluster_partitions('plproxyrc_authority',
                                      ARRAY['dbname=plproxyrc_authority']);
SELECT plproxy.set_remote_config(TRUE, TRUE, TRUE, 'plproxyrc_authority');
SELECT * FROM plproxy.get_cluster_partitions('plproxyrc_authority');
COMMIT;