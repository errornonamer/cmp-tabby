#!/bin/sh

cd $(dirname $0)
# I actually don't know if this is needed, it's completely useless if the plugin manager pulls the submodules too.
# But better safe than sorry
git submodule update --init --recursive --single-branch --depth=1 ./tabby &&
cd tabby

# tabby fails to build without this nasty bloat at the moment
# My brother in Christ, if we wanted enterprise features we wouldn't have localhost as endpoint
features="ee"

while [ "$1" != "" ]; do
    case $1 in
        "--cuda") features="$features,cuda"; shift;;
        "--rocm") features="$features,rocm"; shift;;
        "--vulkan") features="$features,vulkan"; shift;;
        "--oapi") features="$features,experimental-http"; shift;;
    esac
done

cargo build --release --package="tabby" --no-default-features --features "$features"
