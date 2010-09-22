#!/bin/sh
#set -x

cd $(dirname "$0")

HERE=$(dirname $0)
BASE_DIR=../..
AUTHORITY_DB=plproxyrc_authority
PLPROXYRC_FILE=${BASE_DIR}/plproxyrc.sql
PLPROXY_LANG_FILE=${BASE_DIR}/test/schema/002_plproxy.sql
NONRC_AUTHORITY_DB=plproxy_authority
SQL_DIR="${HERE}/sql"
PLPROXY_NONRC_FILE=${SQL_DIR}/nonrc_plproxy.sql

NEW_CLUSTER=new-cluster
NEW_CLUSTER_2=new-cluster-2

cleanup()
{
    for db in "${AUTHORITY_DB}" "${NONRC_AUTHORITY_DB}" \
        plproxyrc_caching_rc plproxyrc_caching_leaf_rc \
        plproxyrc_non_caching_rc plproxyrc_non_caching_leaf_rc \
        plproxyrc_caching plproxyrc_caching_leaf \
        plproxyrc_non_caching plproxyrc_non_caching_leaf
    do
        psql -q -d postgres -c "DROP DATABASE ${db}"
    done
}

setup_rc()
{
    DB="${AUTHORITY_DB}"
    psql -q -d postgres -c "CREATE DATABASE ${DB}"
    psql -q -d "${AUTHORITY_DB}" -c "CREATE LANGUAGE plpgsql"
    psql -q -d "${AUTHORITY_DB}" -f "${PLPROXY_LANG_FILE}"
    psql -q -d "${AUTHORITY_DB}" -f "${PLPROXYRC_FILE}"
    
    for REMOTE_DB in plproxyrc_caching_rc plproxyrc_caching_leaf_rc \
        plproxyrc_non_caching_rc plproxyrc_non_caching_leaf_rc
    do
        psql -q -d postgres -c "CREATE DATABASE ${REMOTE_DB} WITH TEMPLATE ${DB}";
        psql -q -d "${REMOTE_DB}" -f "${SQL_DIR}/${REMOTE_DB}.sql"
    done
    
# create default config in authority that does not exist in remotes
    psql -q -d "${DB}" -c "SELECT plproxy.set_cluster_config_default_value('connection_lifetime', '30')"
    psql -q -d "${DB}" -c "SELECT plproxy.set_cluster_config_default_value('query_timeout', '30')"
# create new cluster in authority that does not exist in remotes
    psql -q -d "${DB}" -c "SELECT plproxy.new_cluster_partitions('${NEW_CLUSTER}', ARRAY['new-cluster-partition-1', 'new-cluster-partition-2'])"
    psql -q -d "${DB}" -c "SELECT plproxy.new_cluster_partitions('${NEW_CLUSTER_2}', ARRAY['new-cluster-2-partition-1', 'new-cluster-2-partition-2'])"
    psql -q -d "${DB}" -c "SELECT plproxy.set_cluster_config_value('${NEW_CLUSTER_2}', 'query_timeout', '60')"

}

setup_nonrc()
{
    DB="${NONRC_AUTHORITY_DB}"
    psql -q -d postgres -c "CREATE DATABASE ${DB}"
    psql -q -d "${DB}" -c "CREATE LANGUAGE plpgsql"
    psql -q -d "${DB}" -f "${PLPROXY_LANG_FILE}"
    psql -q -d "${DB}" -f "${PLPROXY_NONRC_FILE}"
    
    for REMOTE_DB in plproxyrc_caching plproxyrc_caching_leaf \
        plproxyrc_non_caching plproxyrc_non_caching_leaf
    do
        psql -q -d postgres -c "CREATE DATABASE ${REMOTE_DB} WITH TEMPLATE ${AUTHORITY_DB}";
        psql -q -d "${REMOTE_DB}" -f "${SQL_DIR}/${REMOTE_DB}.sql"
    done
}

setup()
{
  setup_rc
  setup_nonrc
}

get_settings()
{
for REMOTE_DB in plproxyrc_caching plproxyrc_caching_leaf plproxyrc_non_caching plproxyrc_non_caching_leaf
do
  echo "get_settings: ${REMOTE_DB}"
  psql -d ${REMOTE_DB} -c "SELECT * FROM plproxy.remote_config()"
done
}

test_clusters()
{
for REMOTE_DB in plproxyrc_caching plproxyrc_caching_leaf \
    plproxyrc_non_caching plproxyrc_non_caching_leaf \
    plproxyrc_caching_rc plproxyrc_caching_leaf_rc \
    plproxyrc_non_caching_rc plproxyrc_non_caching_leaf_rc
do
  echo "test_clusters: ${REMOTE_DB}"
  for CLUSTER in ${NEW_CLUSTER} ${NEW_CLUSTER_2}
  do
      psql -d ${REMOTE_DB} -c "SELECT plproxy.get_cluster_version('${CLUSTER}')"
      psql -d ${REMOTE_DB} -c "SELECT * FROM plproxy.get_cluster_partitions('${CLUSTER}')"
      psql -d ${REMOTE_DB} -c "SELECT * FROM plproxy.get_cluster_config('${CLUSTER}')"
  done
done
}

dotest()
{
    test_clusters
    for REMOTE_DB in plproxyrc_caching_leaf plproxyrc_non_caching_leaf \
        plproxyrc_caching_leaf_rc plproxyrc_non_caching_leaf_rc
    do
        echo ${REMOTE_DB}
        for CLUSTER in ${NEW_CLUSTER} ${NEW_CLUSTER_2}
        do
            echo ${CLUSTER}
            psql -d ${REMOTE_DB} -c "SELECT plproxy.get_cluster_version('${CLUSTER}')"
            psql -d ${REMOTE_DB} -c "SELECT * FROM plproxy.get_cluster_partitions('${CLUSTER}')"
            psql -d ${REMOTE_DB} -c "SELECT * FROM plproxy.get_cluster_config('${CLUSTER}')"
        done
    done
    test_clusters
}

set -e
setup
get_settings
dotest
dotest
cleanup
