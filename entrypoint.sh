#!/bin/sh

set -eu

# Telegram Bot API endpoint
TELEGRAM_API="https://api.telegram.org/bot${INPUT_TOKEN}"

# Default values
PARSE_MODE="${INPUT_FORMAT:-}"
DISABLE_WEB_PAGE_PREVIEW="${INPUT_DISABLE_WEB_PAGE_PREVIEW:-false}"
DISABLE_NOTIFICATION="${INPUT_DISABLE_NOTIFICATION:-false}"

# Build message content
if [ -n "${INPUT_MESSAGE_FILE:-}" ] && [ -f "${INPUT_MESSAGE_FILE}" ]; then
  MESSAGE=$(cat "${INPUT_MESSAGE_FILE}")
elif [ -n "${INPUT_MESSAGE:-}" ]; then
  MESSAGE="${INPUT_MESSAGE}"
else
  # Default message for GitHub Actions
  MESSAGE="🔔 *GitHub Actions*

📦 Repository: \`${GITHUB_REPOSITORY:-unknown}\`
🔀 Event: \`${GITHUB_EVENT_NAME:-unknown}\`
👤 Actor: \`${GITHUB_ACTOR:-unknown}\`
🔗 [View Workflow](${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-}/actions/runs/${GITHUB_RUN_ID:-})"
fi

# Function to send text message
send_message() {
  local chat_id="$1"
  local message="$2"
  local thread_id="${3:-}"
  
  # Build JSON payload
  JSON_PAYLOAD=$(cat <<EOF
{
  "chat_id": "${chat_id}",
  "text": $(echo "$message" | jq -Rs .),
  "disable_web_page_preview": ${DISABLE_WEB_PAGE_PREVIEW},
  "disable_notification": ${DISABLE_NOTIFICATION}
EOF
)

  # Add parse_mode if set
  if [ -n "${PARSE_MODE}" ]; then
    JSON_PAYLOAD="${JSON_PAYLOAD}, \"parse_mode\": \"${PARSE_MODE}\""
  fi

  # Add message_thread_id if set (for topic support)
  if [ -n "${thread_id}" ]; then
    JSON_PAYLOAD="${JSON_PAYLOAD}, \"message_thread_id\": ${thread_id}"
  fi

  JSON_PAYLOAD="${JSON_PAYLOAD}}"

  # Send request
  RESPONSE=$(curl -s -X POST "${TELEGRAM_API}/sendMessage" \
    -H "Content-Type: application/json" \
    -d "${JSON_PAYLOAD}")

  # Check response
  OK=$(echo "$RESPONSE" | jq -r '.ok')
  if [ "$OK" != "true" ]; then
    ERROR_DESC=$(echo "$RESPONSE" | jq -r '.description // "Unknown error"')
    echo "Error sending message: ${ERROR_DESC}"
    exit 1
  fi

  MESSAGE_ID=$(echo "$RESPONSE" | jq -r '.result.message_id')
  echo "Message sent successfully! (message_id: ${MESSAGE_ID})"

  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    echo "message_id=${MESSAGE_ID}" >> "${GITHUB_OUTPUT}"
  fi
}

# Function to delete a previously sent message (failures are non-fatal)
delete_message() {
  local chat_id="$1"
  local message_id="$2"

  RESPONSE=$(curl -s -X POST "${TELEGRAM_API}/deleteMessage" \
    --data-urlencode "chat_id=${chat_id}" \
    --data-urlencode "message_id=${message_id}")

  if [ "$(echo "$RESPONSE" | jq -r '.ok')" = "true" ]; then
    echo "🗑️ Deleted message ${message_id}"
  else
    echo "Warning: could not delete message ${message_id}: $(echo "$RESPONSE" | jq -r '.description // "Unknown error"')"
  fi
}

# Function to send photo
send_photo() {
  local chat_id="$1"
  local photo="$2"
  local caption="${3:-}"
  local thread_id="${4:-}"

  FORM_DATA="-F chat_id=${chat_id} -F photo=@${photo}"
  
  if [ -n "${caption}" ]; then
    FORM_DATA="${FORM_DATA} -F caption=${caption}"
  fi
  
  if [ -n "${PARSE_MODE}" ]; then
    FORM_DATA="${FORM_DATA} -F parse_mode=${PARSE_MODE}"
  fi

  if [ -n "${thread_id}" ]; then
    FORM_DATA="${FORM_DATA} -F message_thread_id=${thread_id}"
  fi

  RESPONSE=$(eval curl -s -X POST "${TELEGRAM_API}/sendPhoto" ${FORM_DATA})

  OK=$(echo "$RESPONSE" | jq -r '.ok')
  if [ "$OK" != "true" ]; then
    ERROR_DESC=$(echo "$RESPONSE" | jq -r '.description // "Unknown error"')
    echo "Error sending photo: ${ERROR_DESC}"
    exit 1
  fi

  echo "Photo sent successfully!"
}

# Function to send document
send_document() {
  local chat_id="$1"
  local document="$2"
  local caption="${3:-}"
  local thread_id="${4:-}"

  FORM_DATA="-F chat_id=${chat_id} -F document=@${document}"
  
  if [ -n "${caption}" ]; then
    FORM_DATA="${FORM_DATA} -F caption=${caption}"
  fi
  
  if [ -n "${PARSE_MODE}" ]; then
    FORM_DATA="${FORM_DATA} -F parse_mode=${PARSE_MODE}"
  fi

  if [ -n "${thread_id}" ]; then
    FORM_DATA="${FORM_DATA} -F message_thread_id=${thread_id}"
  fi

  RESPONSE=$(eval curl -s -X POST "${TELEGRAM_API}/sendDocument" ${FORM_DATA})

  OK=$(echo "$RESPONSE" | jq -r '.ok')
  if [ "$OK" != "true" ]; then
    ERROR_DESC=$(echo "$RESPONSE" | jq -r '.description // "Unknown error"')
    echo "Error sending document: ${ERROR_DESC}"
    exit 1
  fi

  echo "Document sent successfully!"
}

# Main execution
echo "🚀 Telegram GitHub Action"
echo "========================="

# Validate required inputs
if [ -z "${INPUT_TOKEN:-}" ]; then
  echo "Error: Telegram bot token is required"
  exit 1
fi

if [ -z "${INPUT_TO:-}" ]; then
  echo "Error: Telegram chat ID is required"
  exit 1
fi

THREAD_ID="${INPUT_MESSAGE_THREAD_ID:-}"

# Send text message
if [ -n "${MESSAGE}" ]; then
  echo "📤 Sending message to chat: ${INPUT_TO}"
  if [ -n "${THREAD_ID}" ]; then
    echo "📌 Topic/Thread ID: ${THREAD_ID}"
  fi
  send_message "${INPUT_TO}" "${MESSAGE}" "${THREAD_ID}"
  if [ -n "${INPUT_DELETE_MESSAGE_ID:-}" ]; then
    delete_message "${INPUT_TO}" "${INPUT_DELETE_MESSAGE_ID}"
  fi
fi

# Send photo if provided
if [ -n "${INPUT_PHOTO:-}" ]; then
  echo "📷 Sending photo: ${INPUT_PHOTO}"
  send_photo "${INPUT_TO}" "${INPUT_PHOTO}" "${MESSAGE}" "${THREAD_ID}"
fi

# Send document if provided
if [ -n "${INPUT_DOCUMENT:-}" ]; then
  echo "📄 Sending document: ${INPUT_DOCUMENT}"
  send_document "${INPUT_TO}" "${INPUT_DOCUMENT}" "" "${THREAD_ID}"
fi

echo "✅ Done!"
