#!/bin/bash

outdir=$1
shift

VERSION=`cat ./version`

OUTFILE=${outdir}/resticbk_${VERSION}_linux.tar.xz

tar c --transform 's,^./,resticbk/,' \
  --exclude=.git \
  --exclude=.gitignore \
  --exclude=build.sh \
  . \
  | xz -zc -T10 > $OUTFILE
