#! /bin/bash

echo "I will do what I have to do: $@"

if [[ ! -d /presign/empty ]]; then
  echo "Presign is mounted. Copying unsigned packages there."
  cp -vr /sourcepkg/* /presign/
fi

if [[ ! -d /postsign/empty ]]; then
  echo "Postsign is mounted. Uploading packages from there."
  cd /postsign/ubuntu
  ls -la *_source.changes
  dput --unchecked ppa:rpardini/adoptopenjdk *_source.changes
fi
