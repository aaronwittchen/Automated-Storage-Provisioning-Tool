#!/bin/bash

# Use quotes around the path because of spaces
rsync -avz --exclude '.git' --exclude 'logs' \
  "/mnt/c/Users/theon/Desktop/Automated Storage Provisioning Tool/" \
  yeah@192.168.68.105:/home/yeah/storage-provisioning/
