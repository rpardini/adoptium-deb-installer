#! /bin/bash

echo "I will do what I have to do: $@"

if [[ ! -d /presign/empty ]]; then
  echo "Presign is mounted. Copying unsigned packages there."
  cp -v /sourcepkg/* /presign/
fi

if [[ ! -d /postsign/empty ]]; then
  echo "Postsign is mounted. Uploading packages from there."
  cd /postsign
  dput --unchecked ppa:rpardini/adoptopenjdk *_source.changes
fi
