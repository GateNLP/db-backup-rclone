function check_config() {
  # Sanity check rclone configuration
  if [ -z "${REMOTE_NAME}" ]; then
    echo "You need to specify the REMOTE_NAME environment variable"
    exit 1
  fi

  # If an UPLOAD_PREFIX was provided, ensure it ends with a slash
  if [ -n "${UPLOAD_PREFIX}" ]; then
    UPLOAD_PREFIX="${UPLOAD_PREFIX%/}/"
  fi

  if [ -z "${BACKUP_DATABASES}" -a "${BACKUP_ALL}" != "true" ]; then
    echo "You need to set the BACKUP_DATABASES environment variable, or set BACKUP_ALL=true to dump all databases."
    exit 1
  fi
}

# Check whether the given string contains any commas, i.e. if splitting on
# comma would yield more than one item.
function has_comma() {
  case "$1" in
    *,*)
      return 0
    ;;
    *)
      return 1
    ;;
  esac
}

# Basic sanitizing of destination file names
function check_filename() {
  case "$1" in
    /*)
      echo "Destination file name may not start with slash"
      exit 2
    ;;
    *../*)
      echo "Destination file name may not include ../ path segments"
      exit 2
    ;;
  esac
}

function encrypting() {
  if [ -n "${ENCRYPT_RECIPIENTS}" -o -n "${ENCRYPT_RECIPIENTS_FILE}" ]; then
    return 0
  else
    return 1
  fi
}

function post_process() {
  if encrypting; then
    if [ -n "${ENCRYPT_RECIPIENTS}" ]; then
      RAGE_OPTS=""
      for RECIP in ${ENCRYPT_RECIPIENTS} ; do
        RAGE_OPTS="$RAGE_OPTS -r $RECIP"
      done
      gzip | rage $RAGE_OPTS
    else
      gzip | rage -R "${ENCRYPT_RECIPIENTS_FILE}"
    fi
  else
    gzip
  fi
}

# Upload a directory full of files to the destination location in the rclone remote
function upload() {
  DIR="$1"

  rclone copy "$DIR" "${REMOTE_NAME%:}:${UPLOAD_PREFIX}"
}

# The main entrypoint for both postgresql and mariadb backups.
# Expects the DB-specific entrypoint script to have defined
# two functions, do_dump_all to dump all databases, and
# do_dump_one that takes a single parameter for the name of
# the database, and dumps that single database.
function do_backup() {
  check_config

  touch /tmp/started-at

  BACKUP_DIR=$(mktemp -d /scratch/backup.XXXXXX)
  trap 'rm -rf $BACKUP_DIR' EXIT

  if [ "${BACKUP_ALL}" = "true" ]; then
    DEST_FILE_PATTERN="all_%Y-%m-%dT%H-%M-%SZ.sql.gz"

    if [ -n "${BACKUP_FILE_NAME}" ]; then
      DEST_FILE_NO_GZ="${BACKUP_FILE_NAME%.gz}"
      DEST_FILE_PATTERN="${BACKUP_FILE_NAME%.sql}.sql.gz"
    fi

    DEST_FILE=$( date -r /tmp/started-at +"$DEST_FILE_PATTERN" | sed -e 's/[^a-zA-Z0-9_.\/]\+/-/g' -e 's/^-\|-$//g' )

    check_filename "${DEST_FILE}"

    if encrypting; then
      DEST_FILE="${DEST_FILE%.age}.age"
    fi

    echo "Creating dump of all databases..."
    mkdir -p "$(dirname "${BACKUP_DIR}/${DEST_FILE}")"
    do_dump_all "$@" | post_process > "${BACKUP_DIR}/${DEST_FILE}"
  else
    DEST_FILE_PATTERN='${DB}-%Y-%m-%dT%H-%M-%SZ.sql.gz'

    if [ -n "${BACKUP_FILE_NAME}" ]; then
      DEST_FILE_NO_GZ="${BACKUP_FILE_NAME%.gz}"
      DEST_FILE_PATTERN="${BACKUP_FILE_NAME%.sql}.sql.gz"
    fi
    case "$DEST_FILE_PATTERN" in
      *\$DB*|*\$\{DB\}*)
        # This is ok
      ;;
      *)
        if has_comma "$DB"; then
          echo 'Destination file pattern does not include a $DB placeholder, and multiple databases are being dumped - this is not allowed as the later dump files would overwrite the first one.'
          exit 3
        fi
    esac

    OIFS="$IFS"
    IFS=','
    for DB in $BACKUP_DATABASES
    do
      IFS="$OIFS"
      export DB
      THIS_DEST_FILE_PATTERN="$( echo -n "${DEST_FILE_PATTERN}" | envsubst '$DB' )"
      DEST_FILE=$( date -r /tmp/started-at +"$THIS_DEST_FILE_PATTERN" | sed -e 's/[^a-zA-Z0-9_.\/]\+/-/g' -e 's/^-\|-$//g' )

      check_filename "${DEST_FILE}"

      if encrypting; then
        DEST_FILE="${DEST_FILE%.age}.age"
      fi

      echo "Creating dump of database ${DB}..."
      mkdir -p "$(dirname "${BACKUP_DIR}/${DEST_FILE}")"
      do_dump_one "$DB" "$@" | post_process > "${BACKUP_DIR}/${DEST_FILE}"
    done
  fi

  echo "Uploading backup files"
  upload "$BACKUP_DIR"
}