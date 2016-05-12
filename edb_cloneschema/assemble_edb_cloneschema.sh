#!/bin/sh
cat edb_cloneschema--1.0.sql.header >edb_cloneschema--1.0.sql
cat local/*.sql >>edb_cloneschema--1.0.sql
cat remote/*.sql >>edb_cloneschema--1.0.sql

mkdir edb_cloneschema
mv edb_cloneschema--1.0.sql edb_cloneschema/
cp edb_cloneschema.control edb_cloneschema/
cp makefile edb_cloneschema/
cp installation.txt edb_cloneschema/

[ -f edb_cloneschema.tar.gz ] && rm -f edb_cloneschema.tar.gz
tar czf edb_cloneschema.tar.gz edb_cloneschema/
rm -rf edb_cloneschema
rm -f edb_cloneschema--1.0.sql
