#!/bin/bash
#
# Authors: Paris Moschovakos
# Email: paris@moschovakos.com
# Date: 24 July 2023
#

function usage {
    echo "Usage: $0 [OPTIONS] <firmware.dtbo-name>"
    echo "Load a device tree overlay firmware into a running Zynq system."
    echo
    echo "Options:"
    echo "  -h, --help    Show this help message and exit"
    echo "  -l, --list    List available firmware files"
    echo
    echo "The <firmware.dtbo-name> is the name of the .dtbo firmware file to be loaded."
}

function list_firmware {
    echo "Firmware files:"
    for file in /lib/firmware/*.dtbo; do
        basename "$file"
    done
}

while getopts ":lh" opt; do
    case ${opt} in
        l)
            list_firmware
            exit 0
            ;;
        h)
            usage
            exit 0
            ;;
        \?)
            echo "Invalid option: $OPTARG" 1>&2
            usage
            exit 1
            ;;
    esac
done
shift $((OPTIND -1))

if [[ "$1" == "--list" ]]; then
    list_firmware
    exit 0
elif [[ "$1" == "--help" ]]; then
    usage
    exit 0
fi

scriptname="$(basename -- $0)"
if [ -z "$1" ] || [ ! ${1: -5} == ".dtbo" ]
then
    echo "Usage: $scriptname <firmware.dtbo-name>"
    echo "       $scriptname -l or --list to list available firmware"
    exit 1
fi

if [ ! -f "/lib/firmware/$1" ] || [ ! -r "/lib/firmware/$1" ]
then
    echo "Error: Firmware file '$1' does not exist or is not readable"
    exit 1
fi

[ ! -d "/configfs" ] && mkdir /configfs && echo "created /configfs" # Make /configfs if it doesn't exist

mountpoint -q /configfs || mount -t configfs configfs /configfs

if [ $? -ne 0 ]
then
    echo "Error: Failed to mount /configfs"
    exit 1
fi

# ELMBPP-143: Before creating the directory, check if it exists and remove it if necessary
if [ -d "/configfs/device-tree/overlays/emp-firmware" ]; then
    echo "Existing firmware detected. Unloading..."
    rmdir /configfs/device-tree/overlays/emp-firmware
    if [ $? -ne 0 ]; then
        echo "Error: Failed to unload existing firmware"
        exit 1
    fi
fi

mkdir -p /configfs/device-tree/overlays/emp-firmware

if [ $? -ne 0 ]
then
    echo "Error: Failed to create /configfs/device-tree/overlays/emp-firmware"
    exit 1
fi

echo -n "$1" > /configfs/device-tree/overlays/emp-firmware/path

if [ $? -ne 0 ]
then
    echo "Error: Failed to write firmware path"
    exit 1
fi

echo "Firmware '$1' was successfully loaded."