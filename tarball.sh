#!/bin/bash

#d=`date -u '+%Y-%m-%d_%H-%M'`
v=`grep version qiolite.nimble |sed 's/.*= "\(.*\)".*/\1/'`
n="qiolite-$v"
t="$n.tgz"
ln -s . $n
f="$n/Makefile $n/make.inc"
f="$f $n/include/qio.h"
f="$f $n/lib/Makefile $n/lib/make.objs $n/lib/nimbase.h $n/lib/*.c"
tar cvzf $t $f
rm $n

test() {
    if [ ! -e tmp ]; then mkdir tmp; fi
    cd tmp
    rm -rf $n
    tar zxvf ../$t
    cd $n
    make
}

test
