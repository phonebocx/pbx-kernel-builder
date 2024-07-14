#!/bin/bash

CMD=$1
if [ "$CMD" == "-i" ]; then
	echo "Installing patch"
	PCMD="patch -p0"
else
	echo "Removing patch"
	PCMD="patch -R -N -r/dev/null -p0"
fi

# For some reason this flag appears to be moving around in the tarballs.
if grep -q 'cpu_mitigations __ro_after_init =$' kernel/cpu.c; then
	echo "cpu_mitigations setting is on the next line"
	$PCMD < ../../patches/mitigations.patch.nextline
	exit 0
fi

if grep -q 'cpu_mitigations __ro_after_init = CPU' kernel/cpu.c; then
	echo "cpu_mitigations setting is on the same line"
	$PCMD < ../../patches/mitigations.patch.sameline
	exit 0
fi

echo "Could not find cpu mitigations to patch"
exit 99


