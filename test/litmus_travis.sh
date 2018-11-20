#!/usr/bin/env bash

if [ ! -f /tmp/litmus/litmus-0.13.tar.gz ]; then
  echo "call setup_litmus.sh first!"
  exit 1
fi

cd /tmp/litmus/litmus-0.13/

for name in basic copymove props
do
  ./$name http://localhost:3000/
  if [ $? -ne 0 ] ; then
    echo
    echo "*** Litmus ($name) failed to properly complete"
    exit 1
  fi
done

