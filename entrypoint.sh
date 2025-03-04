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
  
  # Pull with retry
  echo "Pulling before pushing the newest commit with rebase"
  MAX_PULL_RETRIES=3
  PULL_RETRY_COUNT=0
  PULL_SUCCESS=false
  
  while [ $PULL_RETRY_COUNT -lt $MAX_PULL_RETRIES ] && [ "$PULL_SUCCESS" = "false" ]; do
    if git pull origin "$OUTPUT_BRANCH" --rebase; then
      PULL_SUCCESS=true
      echo "Pull successful on attempt $((PULL_RETRY_COUNT+1))"
    else
      PULL_RETRY_COUNT=$((PULL_RETRY_COUNT+1))
      if [ $PULL_RETRY_COUNT -lt $MAX_PULL_RETRIES ]; then
        SLEEP_TIME=$((PULL_RETRY_COUNT * 5))
        echo "Pull failed, retrying in $SLEEP_TIME seconds (attempt $PULL_RETRY_COUNT of $MAX_PULL_RETRIES)..."
        sleep $SLEEP_TIME
      else
        echo "Failed to pull after $MAX_PULL_RETRIES attempts."
        exit 1
      fi
    fi
  done
  
  # Push with retry
  echo "Pushing git commit"
  MAX_PUSH_RETRIES=3
  PUSH_RETRY_COUNT=0
  PUSH_SUCCESS=false
  
  while [ $PUSH_RETRY_COUNT -lt $MAX_PUSH_RETRIES ] && [ "$PUSH_SUCCESS" = "false" ]; do
    if git push -u origin HEAD:"$OUTPUT_BRANCH"; then
      PUSH_SUCCESS=true
      echo "Push successful on attempt $((PUSH_RETRY_COUNT+1))"
    else
      PUSH_RETRY_COUNT=$((PUSH_RETRY_COUNT+1))
      if [ $PUSH_RETRY_COUNT -lt $MAX_PUSH_RETRIES ]; then
        SLEEP_TIME=$((PUSH_RETRY_COUNT * 5))
        echo "Push failed, retrying in $SLEEP_TIME seconds (attempt $PUSH_RETRY_COUNT of $MAX_PUSH_RETRIES)..."
        sleep $SLEEP_TIME
        # Pull again before retrying push
        git pull origin "$OUTPUT_BRANCH" --rebase
      else
        echo "Failed to push after $MAX_PUSH_RETRIES attempts."
        exit 1
      fi
    fi
  done
else
  echo "No changes detected"
fi
