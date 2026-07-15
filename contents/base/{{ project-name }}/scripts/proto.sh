#!/usr/bin/env bash
set -e

PROTO_DIR="proto"
OUT_DIR="src/generated"

mkdir -p "$OUT_DIR"

# All protos, including vendored ones in subdirectories (e.g. grpc/health/v1).
PROTO_FILES=$(find "$PROTO_DIR" -name '*.proto')

# --descriptor_set_out produces the serialized FileDescriptorSet that the gRPC server
# reflection service (wired in src/servicer.ts) serves to dynamic clients.
./node_modules/.bin/grpc_tools_node_protoc \
  --plugin=protoc-gen-ts_proto=./node_modules/.bin/protoc-gen-ts_proto \
  --ts_proto_out="$OUT_DIR" \
  --ts_proto_opt=outputServices=nice-grpc,outputServices=generic-definitions,useExactTypes=false \
  --descriptor_set_out="$OUT_DIR/protoset.bin" \
  --include_imports \
  --proto_path="$PROTO_DIR" \
  $PROTO_FILES

echo "Proto compiled to $OUT_DIR"
