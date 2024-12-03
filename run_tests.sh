#!/usr/bin/env sh
curl --silent --fail http://app:8080 | grep 'PHP 8.3'
