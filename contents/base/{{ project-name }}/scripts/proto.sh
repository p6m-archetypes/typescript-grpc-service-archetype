#!/usr/bin/env bash
set -e

PROTO_DIR="proto"
OUT_DIR="src/generated"

mkdir -p "$OUT_DIR"

./node_modules/.bin/grpc_tools_node_protoc \
  --plugin=protoc-gen-ts_proto=./node_modules/.bin/protoc-gen-ts_proto \
  --ts_proto_out="$OUT_DIR" \
  --ts_proto_opt=outputServices=nice-grpc,outputServices=generic-definitions,useExactTypes=false \
  --proto_path="$PROTO_DIR" \
  "$PROTO_DIR"/*.proto

echo "Proto compiled to $OUT_DIR"
