#!/bin/sh

set -e
set -x

if [ -z "$INPUT_SOURCE_FILE" ]
then
  echo "Source file must be defined"
  return 1
fi

if [ -z "$INPUT_GIT_SERVER" ]
then
  INPUT_GIT_SERVER="github.com"
fi

if [ -z "$INPUT_DESTINATION_BRANCH" ]
then
  INPUT_DESTINATION_BRANCH=main
fi
OUTPUT_BRANCH="$INPUT_DESTINATION_BRANCH"

CLONE_DIR=$(mktemp -d)

echo "Cloning destination git repository"
git config --global user.email "$INPUT_USER_EMAIL"
git config --global user.name "$INPUT_USER_NAME"
git clone --single-branch --branch $INPUT_DESTINATION_BRANCH "https://x-access-token:$API_TOKEN_GITHUB@$INPUT_GIT_SERVER/$INPUT_DESTINATION_REPO.git" "$CLONE_DIR"

if [ ! -z "$INPUT_RENAME" ]
then
  echo "Setting new filename: ${INPUT_RENAME}"
  DEST_COPY="$CLONE_DIR/$INPUT_DESTINATION_FOLDER/$INPUT_RENAME"
else
  DEST_COPY="$CLONE_DIR/$INPUT_DESTINATION_FOLDER"
fi

echo "Copying contents to git repo"
mkdir -p $CLONE_DIR/$INPUT_DESTINATION_FOLDER
if [ -z "$INPUT_USE_RSYNC" ]
then
  cp -R "$INPUT_SOURCE_FILE" "$DEST_COPY"
else
  echo "rsync mode detected"
  rsync -avrh "$INPUT_SOURCE_FILE" "$DEST_COPY"
fi

cd "$CLONE_DIR"

if [ ! -z "$INPUT_DESTINATION_BRANCH_CREATE" ]
then
  echo "Creating new branch: ${INPUT_DESTINATION_BRANCH_CREATE}"
  git checkout -b "$INPUT_DESTINATION_BRANCH_CREATE"
  OUTPUT_BRANCH="$INPUT_DESTINATION_BRANCH_CREATE"
fi

if [ -z "$INPUT_COMMIT_MESSAGE" ]
then
  INPUT_COMMIT_MESSAGE="Update from https://$INPUT_GIT_SERVER/${GITHUB_REPOSITORY}/commit/${GITHUB_SHA}"
fi

echo "Adding git commit"
git add .
if git status | grep -q "Changes to be committed"
then
git commit --message "$INPUT_COMMIT_MESSAGE"
echo ""
echo "-----------------------------"
echo "-- GIT PUSH"
echo "-----------------------------"
echo "[RUNNING]:   git push -u origin HEAD:"$OUTPUT_BRANCH""
  git push -u origin HEAD:"$OUTPUT_BRANCH"

if [ $? -eq 0 ]; then
  echo "[SUCCESS]: Pushed successfully!"
  exit 0
else
  echo "[ERROR]: Push failed. Trying to pull --rebase"
  git pull --rebase origin $OUTPUT_BRANCH
  if [ $? -eq 0 ]; then
    echo "[SUCCESS]: Pull worked! Trying to push again..."
    echo "-----------------------------"
    echo "-- GIT PUSH"
    echo "-----------------------------"
    git push -u origin HEAD:"$OUTPUT_BRANCH" || exit 1
  else
    echo "********************************************************************************************"
    echo "[ERROR]: Pull failed..."
    echo "[ERROR]: Seems there was a conflict during rebase with origin. Printing debug logs below and exiting."
    echo "********************************************************************************************"
    echo "***  DEBUG"
    echo "********************************************************************************************"
    echo "[INFO] Git status"
    git status
    echo "------------------------------------------------------"
    echo "[INFO] Git log"
    git log -n 5
    echo "------------------------------------------------------"
    echo "[INFO] Git diff"
    git diff
    echo "********************************************************************************************"
    exit 1
  fi
fi
else
  echo "No changes detected"
fi
