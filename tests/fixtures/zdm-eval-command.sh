#!/usr/bin/env bash
zdmcli migrate database \
  -sourcenode 'source-db.example.internal' \
  -targetnode 'target-ssh.example.internal' \
  -srcarg3 'sudo_location:/usr/bin/sudo' \
  -tgtarg3 'sudo_location:/usr/bin/sudo' \
  -targethome '/u02/app/oracle/product/19.0.0.0/dbhome_1' \
  -tdekeystorepasswd \
  -eval
