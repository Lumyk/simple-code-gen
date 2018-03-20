#!/bin/bash

#setup's
dir_name="generated" #directory name for generated classes
schema=$(find . -name schema.json) #path to GraphQL schema (schema.json)
paths=$(find . -name *.graphql) #path's to GraphQL request files

#dependencies
if ! brew ls --versions libgraphqlparser > /dev/null; then
  brew install libgraphqlparser
fi

if [ $(gem list -i "^graphql-libgraphqlparser$") == false ]; then
  gem install graphql-libgraphqlparser
fi

mkdir -p $dir_name && rm -fr $dir_name/*
graphql=NULL

for i in $paths; do
  if [ $graphql == NULL ]; then
    graphql="$i"
  else
    graphql="$graphql,$i"
  fi
done

SCRIPTPATH="$( cd "$(dirname "$0")" ; pwd -P )"
ruby $SCRIPTPATH/code-gen.rb --schema $schema --graphql $graphql
