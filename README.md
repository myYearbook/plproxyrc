plproxyrc - PL/Proxy Remote Config
===================================
High-level overview:

 * Function API for table-based PL/Proxy cluster configuration
 * Remote lookup of cluster configuration (via PL/Proxy)
 * Local caching of remote cluster configuration

PL/Proxy provides a very nice method of performing queries on remote Postgres
servers. It has a very simple interface.

It implement three functions required for PL/Proxy:

 1. `plproxy.get_cluster_partitions` provides named collections of connections
   (*cluster* being the name, *partitions* being the connection collection)
 2. `plproxy.get_cluster_config` provides per-cluster connection configuration
 3. `plproxy.get_cluster_version` provides a simple method of allowing PL/Proxy
   flush its cached connections if the version changes.

plproxyrc also provides a set of functions for managing cluster configuration.

(The configuration itself is stored in Postgres tables in the plproxy schema,
but you should never need to access the tables directly: the function API
should provide everything you need for managing PL/Proxy clusters. If there's
something missing, drop me a line.)

API functions
-------------
Any functions not listed here are not considered part of the public API
and may change between versions.

### Required by PL/Proxy (and provided by plproxyrc)
plproxyrc provides the three functions used by the PL/Proxy library.

 * `plproxy.get_cluster_version(in_cluster_name TEXT) RETURNS INT`
 * `plproxy.get_cluster_partitions(in_cluster_name TEXT) RETURNS SETOF TEXT`
 * `plproxy.get_cluster_config(in_cluster_name TEXT, OUT key TEXT, OUT val TEXT) RETURNS SETOF RECORD`

### Provided by plproxyrc

#### Configuring PL/Proxy cluster partitions
 * `plproxy.new_cluster_partitions(in_cluster TEXT, in_cluster_partitions TEXT[], OUT cluster_version INT) RETURNS INT`
 * `plproxy.set_cluster_partitions(in_cluster TEXT, in_cluster_partitions TEXT[], OUT cluster_version INT) RETURNS INT`
 * `plproxy.delete_cluster(in_cluster TEXT) RETURNS BOOLEAN`
 * `plproxy.delete_cached_clusters() RETURNS BOOLEAN`

#### Configuring PL/Proxy clusters
 * `plproxy.set_cluster_config_default_value(in_param_name TEXT, in_param_value TEXT) RETURNS BOOLEAN`
 * `plproxy.cluster_config_default_values(OUT param_name TEXT, OUT param_value TEXT) RETURNS SETOF RECORD`
 * `plproxy.set_cluster_config_value(in_cluster TEXT, in_param_name TEXT, in_param_value TEXT) RETURNS BOOLEAN`
 * `plproxy.delete_cluster_config_value(in_cluster TEXT, in_param_name TEXT) RETURNS BOOLEAN`
 * `plproxy.delete_cluster_config_values(in_cluster TEXT) RETURNS BOOLEAN`

#### Configuring plproxyrc
 * `plproxy.set_remote_config_settings(in_is_recursive BOOLEAN, in_does_cache_clusters BOOLEAN, in_parent_has_plproxyrc BOOLEAN, in_parent_cluster TEXT) RETURNS BOOLEAN`

Requirements
============
 * [PL/Proxy](http://pgfoundry.org/projects/plproxy/)
 * PL/pgSQL
 * Tested with Postgres 8.4.4

Getting started
===============
Load plproxyrc.sql into target database:
    psql --dbname target --file plproxyrc.sql

Ownership of the objects is assigned to the user loading the script.
Only this user or a superuser may use the objects.

Warning
=======
plproxyrc does not check for loops. It's possible to configure plproxyrc such
that the parent cluster directly or indirectly point at each other, creating an
infinite loop. Caveat configurator.

Testing
=======
 Ruby and Rake are required for testing.

There are two sets of tests:
 * [pgTAP][] unit tests for non-PL/Proxy functions such as configuration management
 * remote functional PL/Proxy tests for PL/Proxy functions

pgTAP unit tests
----------------
The pgTAP tests
 * create a new database
 * load pgTAP, plproxyrc, and plproxyrc unit test SQL files
 * run the unit tests, and
 * drop the database

To run the pgTAP tests:
    rake test

The pgTAP library included with plproxyrc requires Postgres 8.4

[pgTAP]: http://pgtap.org/ "pgTAP"

PL/Proxy functional tests
-------------------------
The functional tests
 * create new databases
 * load PL/Proxy and plproxyrc as appropriate
 * run PL/Proxy functions requiring lookups
 * drop the created databases
 * compare output of test with expected output

To run the functional tests:
    rake test_remote

TODO
====
 * Streamline remote PL/Proxy tests -- should be shorter
 * Confirm code coverage of unit and remote tests
 * Simplify directory layout
 * Make PGXS-compatible? (install in share/contrib?)
 * Include documentation for all functions in function bodies.
 * Include documentation for functions in README or elsewhere,
   preferably generated from the function documenation itself.
 * Bump cluster version number when cluster config is updated.
   (Currently only updates when cluster partitions are set.)

Author
------
Michael Glaesemann <michael.glaesemann at myyearbook.com>

Copyright and License
=====================
Copyright (c) 2010, Insider Guides, Inc.
All rights reserved.

Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:

 * Redistributions of source code must retain the above copyright notice,
   this list of conditions and the following disclaimer.

 * Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

 * Neither the name of Insider Guides, Inc., its website properties nor the
   names of its contributors may be used to endorse or promote products derived
   from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
