#!/bin/bash
set -x

# Check if the arguments for port number, security_group_id, and source_security_group_id are provided
if [ $# -ne 3 ]; then
  echo "{\"exists\": false}"
#  echo "Usage: $0 <port_number> <security_group_id> <source_security_group_id>"
  exit 1
fi

port=$1
group_id=$2
source_group_id=$3

# Check if rule already exists
result=$(aws ec2 describe-security-groups \
  --filters Name=group-id,Values=$group_id Name=ip-permission.to-port,Values=$port Name=ip-permission.protocol,Values=tcp Name=ip-permission.group-id,Values=$source_group_id \
  --query 'length(SecurityGroups[])' --output text)

if [ "$result" -eq 1 ]; then
  echo "{\"result\": \"true\"}"
else
  echo "{\"result\": \"false\"}"
fi
