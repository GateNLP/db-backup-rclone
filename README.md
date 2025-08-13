# Database backups with rclone

This is a generalized version of the popular [schickling/dockerfiles](https://github.com/schickling/dockerfiles) container images `postgres-backup-s3` and `mysql-backup-s3`, which take SQL backups of the relevant database type, optionally encrypt the backup file, and upload it to Amazon S3 (or an API-compatible data store).  Those images work well but have a number of limitations:

- the backing store _must_ be S3 or some compatible datastore supported by the `aws` CLI
- authentication must use static credentials supplied in non-standard environment variables `S3_ACCESS_KEY_ID`, etc. (at least for the postgresql backup image)
- the encryption algorithm used by the postgresql image is `aes-256-cbc`, which lacks in-built authentication and has other known shortcomings

This tool uses [rage](https://github.com/str4d/rage) for encryption and [rclone](https://rclone.org) to upload the backup files rather than the `aws` CLI, meaning you can use [any other supported `rclone` backend](https://rclone.org/overview/) as the data store, including but not limited to:

- S3 or compatible data stores, using any authentication method supported by the AWS Go SDK (static credentials, IAM roles for containers, `AssumeRoleWithWebIdentity`, etc.)
- Other cloud storage services such as Google Drive or Google Cloud, Azure Blob or File Storage, Dropbox, and many others
- Private cloud object stores such as OpenStack Swift
- An SFTP, SMB or WebDav file server

## Usage

The `ghcr.io/gatenlp/postgresql-backup-rclone` and `ghcr.io/gatenlp/mariadb-backup-rclone` images are designed to defer where possible to the underlying tools' native configuration mechanisms rather than introducing our own configuration mechanism.  This makes them slightly more complicated to set up when compared to the original `schickling/dockerfiles` images, but opens up the full flexibility of the underlying tools.  The [examples](examples) folder has some sample manifests that show how you might deploy a Kubernetes `CronJob` that does daily backups to a variety of data stores.

There are a small number of environment variables that are interpreted directly by the script:

- `BACKUP_DATABASES`: the names of the databases from the target server that you want to back up, separated by commas.  Each named database will be backed up to a different file.
    - alternatively, you can set `BACKUP_ALL=true` to dump _all_ databases into a single file (the `--all-databases` option to `mysqldump`, or the `pg_dumpall` tool for PostgreSQL)
- `BACKUP_FILE_NAME`: a file name or file name pattern to which the backup will be written.  The pattern may include `strftime` date formatting directives to include the date and time of the backup as part of the file name, and may include subdirectories.  For example `%Y/%m/backup-%Y-%m-%dT%H-%M-%S` would include the full date and time in the file name, and place it in a folder named for the year and month, e.g. `2025/08/backup-2025-08-12T13-45-15`.  The pattern should include only ASCII letters, numbers, `_`, `-`, `/` and `.` characters, anything else will be changed to a hyphen, and a `.sql.gz` suffix will be added if it is not already present.
    - if not using `BACKUP_ALL` mode, the `BACKUP_FILE_NAME` should include a placeholder `$DB` or `${DB}` which will be replaced by the name of the database.  This is _required_ if more than one database is named by `BACKUP_DATABASES`
- `REMOTE_NAME`: name of the `rclone` "remote" that defines the target datastore - this can be either the _name_ of a remote that is configured with standard rclone environment variables or configuration file, or it can be a [_connection string_](https://rclone.org/docs/#connection-strings) starting with `:` that provides the remote configuration inline, e.g. `:s3,env_auth`.  The default value if not specified is `store`, which would then typically be configured with environment variables of the form `RCLONE_CONFIG_STORE_{option}`.
- `UPLOAD_PREFIX`: optional prefix to prepend to the generated file name to give the final location within the rclone remote.  For example, if the remote is S3 this could be the name of the bucket.

## Database connection parameters

The parameters for connection to the database are provided using the native methods of each database client.  Typically this is either a set of environment variables, command-line options, or a bind-mounted configuration file, or a combination of all these.

### PostgreSQL

The [`pg_dump`](https://www.postgresql.org/docs/current/app-pgdump.html) tool can take configuration from environment variables, files, and/or command-line parameters.  In most cases you will probably use the following environment variables:

- `PGHOST`: hostname of the database server
- `PGPORT`: port number, if not the default 5432
- `PGUSER`: username to authenticate
- `PGPASSWORD`: password for that username
    - if you specify `PGPASSWORD_FILE` then the script will read the contents of that file into the `PGPASSWORD` variable
    - alternatively you can provide your own `.pgpass` formatted file with credentials, and reference that with the `PGPASSFILE` environment variable

Any additional command-line options passed to the container will be forwarded unchanged to `pg_dump` or `pg_dumpall` as appropriate.

### MariaDB / MySQL

The [`mariadb-dump`](https://mariadb.com/docs/server/clients-and-utilities/backup-restore-and-import-clients/mariadb-dump) tool can take configuration from [environment variables](https://mariadb.com/docs/server/server-management/install-and-upgrade-mariadb/configuring-mariadb/mariadb-environment-variables), option files, and/or command-line parameters.  In most cases you will probably use the following environment variables or parameters:

- `MYSQL_HOST` or `--host=...`: hostname of the database server
- `MYSQL_TCP_PORT` or `--port=...`: port number, if not the default 3306
- `MYSQL_PWD` or `--password=...`: password for authentication
    - if you specify the environment variable `MYSQL_PWD_FILE` then the script will read the contents of that file into the `MYSQL_PWD` variable
- `--user=...`: username for authentication - note that `mariadb-dump` does not provide an environment variable alternative for this option, it can only be supplied on the command line or in an option file.

Any additional command line options passed to the container will be forwarded unchanged to the `mysqldump` commands`.

Alternatively you can provide the connection and authentication details in a `my.cnf`-style "options file" bind-mounted into the container at `/etc/mysql`, or at some other location if you specify an argument of `--defaults-extra-file=/path/to/my.cnf`.

## Rclone data store configuration

There are three basic ways to configure `rclone` to talk to your data store:

1. use environment variables `RCLONE_CONFIG_STORE_*`
2. bind-mount an `rclone.conf` file into your container, and set `RCLONE_CONFIG=/path/to/rclone.conf`
3. set `REMOTE_NAME` to a full connection string starting with `:`

In most cases option 1 will be the simplest.  The following sections provide examples for common datastore types.

> **Note**: There is no way to pass command line parameters through to `rclone`, but _every_ parameter to `rclone` has an environment variable equivalent - take the long option form, replace the leading `--` with `RCLONE_`, change the remaining hyphens to underscores and convert to upper-case.  E.g. `--max-connections 3` on the command line becomes `RCLONE_MAX_CONNECTIONS=3` in the environment.

### Amazon S3

- `RCLONE_CONFIG_STORE_TYPE=s3`
- `RCLONE_CONFIG_STORE_PROVIDER=AWS`
- `RCLONE_CONFIG_STORE_ENV_AUTH=true`
- If your bucket uses `SSE_KMS` server side encryption then you should also set `RCLONE_IGNORE_CHECKSUM=true`, since SSE breaks the checksum tests that rclone normally attempts to perform
- By default, `rclone` will check whether the bucket exists before uploading to it, and make a `HEAD` request after uploading each file to check that the upload was successful.  These checks require _read_ access to the bucket, so if your credentials have "write-only" permission (i.e. the IAM policy permits `s3:PutObject` but not `s3:GetObject`), then you will need to disable these checks by setting:
    - `RCLONE_S3_NO_CHECK_BUCKET=true`
    - `RCLONE_S3_NO_HEAD=true`

You then need to provide the region name and credentials, in some form that the AWS SDK understands.  The region is set in the variable `AWS_REGION`, e.g. `AWS_REGION=us-east-1`.  For credentials, the most common option is `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` for static credentials, but other supported authentication schemes include

- `AWS_WEB_IDENTITY_TOKEN_FILE`, `AWS_ROLE_ARN` and `AWS_ROLE_SESSION_NAME` to assume an IAM role from a JWT token
- `AWS_CONTAINER_CREDENTIALS_FULL_URI` (and `AWS_CONTAINER_AUTHORIZATION_TOKEN_FILE`) to set an HTTP/HTTPS endpoint that serves temporary credentials, and an authorization token to use when calling it - this is set up for you automatically when using "pod identity" in EKS

`UPLOAD_PREFIX` would then be set to the `bucketname/prefix` where you want to store your backups.

To use server-side encryption with a customer-provided key:

- `RCLONE_S3_SSE_CUSTOMER_ALGORITHM=AES256`
- `RCLONE_S3_SSE_CUSTOMER_KEY=<your key>` or `RCLONE_S3_SSE_CUSTOMER_KEY_BASE64=<your key in base64>`

### S3-compatible service

The same approach works for other services or self-hosted datastores that are compatible with the S3 API, you just need to set `RCLONE_CONFIG_STORE_PROVIDER=Minio` (or whatever provider you are using) and `AWS_ENDPOINT_URL_S3` to point to your provider's endpoint.

### Azure Blob Storage

- `RCLONE_CONFIG_STORE_TYPE=azureblob`

If you are authenticating using a container-level or account-level SAS token then the only other required environment variable would be

- `RCLONE_CONFIG_STORE_SAS_URL=https://accountname.blob.core.windows.net/container?<sastoken>`

For any other authentication style, you must specify the account name

- `RCLONE_CONFIG_STORE_ACCOUNT=accountname`

and then either `RCLONE_CONFIG_STORE_KEY={storage-account-key}` for shared key authentication, or `RCLONE_CONFIG_STORE_ENV_AUTH=true` for Entra ID authentication.  The [`env_auth` option](https://rclone.org/azureblob/#env-auth) will handle authentication with a service principal, workload identity (if running in AKS), or managed service identity as appropriate.

`UPLOAD_PREFIX` would specify the _container_ name and any prefix within that container - the _account_ name is part of the remote definition and comes from `RCLONE_CONFIG_STORE_ACCOUNT` or the SAS URL.

### SFTP

- `RCLONE_CONFIG_STORE_TYPE=sftp`
- `RCLONE_CONFIG_STORE_SHELL_TYPE=none`
- `RCLONE_CONFIG_STORE_HOST=sftp-server-hostname`
- `RCLONE_CONFIG_STORE_USER=myuser`
- `RCLONE_CONFIG_STORE_KEY_FILE=/path/to/privatekey`
- `RCLONE_CONFIG_STORE_KNOWN_HOSTS_FILE=/path/to/known_hosts`

You will need to mount the private key and `known_hosts` file into your container, set `UPLOAD_PREFIX` to the path on the server where you want to store the backup files - relative paths are resolved against the home directory of the authenticating user, if you want to store the files elsewhere then set the prefix to an _absolute_ path (starting with `/`, e.g. `UPLOAD_PREFIX=/mnt/backups`).

### SMB server

- `RCLONE_CONFIG_STORE_TYPE=smb`
- `RCLONE_CONFIG_STORE_SMB_HOST=smb-server-hostname`
- `RCLONE_CONFIG_STORE_SMB_USER=myuser`
- `RCLONE_CONFIG_STORE_SMB_PASS=mypassword`
- `RCLONE_CONFIG_STORE_SMB_DOMAIN=workgroup`

The `UPLOAD_PREFIX` should be of the form `sharename/path`

## Encryption

By default, the SQL dump files are stored as-is in the remote data store.  If this is an off-site backup it may be desirable to have the files encrypted before upload.

These images support encryption using [rage](https://github.com/str4d/rage), which implements the https://age-encryption.org/v1 spec for file encryption.  It encrypts the data stream with a random key using the `ChaCha20-Poly1305` cipher, then encrypts the session key using an elliptic curve asymmetric cipher.  The `rage` implementation can use the SSH `ed25519` key format, and that is the simplest way to enable encryption:

1. Generate a public & private key pair using `ssh-keygen -t ed25519`
2. Mount the _public_ key into your backup container
3. set `ENCRYPT_RECIPIENTS_FILE=/path/to/id_ed25519.pub`

This will encrypt all files using the given public key (adding a `.age` extension to the file name) before uploading them to the data store.  If you need to restore from such a file then you can decrypt it using the corresponding _private_ key, e.g. for PostgreSQL:

```shell
rage -d -i /path/to/id_ed25519 mydb.sql.gz.age | gunzip | psql -X -d newdb
```

Alternatively you can generate standard `age` key pairs using `rage-keygen` and then specify the `age1....` identity string directly in the environment variable `ENCRYPT_RECIPIENTS`, then use the corresponding private keys to decrypt when you need to restore from the backups.


## Developer information

### Building the images

Images are built using `docker buildx bake` - running this on its own will build both the postgresql and mariadb images for your local architecture and load them into your docker image store to be run on your local machine.

To build just one or the other image, specify the name to the `bake` command, e.g. `docker buildx bake mariadb`.

To build multi-platform images and push them to a registry, use:

```shell
PROD=true DBBR_REGISTRY=ghcr.io/gatenlp/ docker buildx bake --push
```

`PROD=true` enables multi-platform image building (your `buildx` builder must be capable of generating these), and `DBBR_REGISTRY` is the registry prefix to which the images should be pushed.  By default the images are tagged with both `:latest` and `:rclone-vX.Y.Z` for the version of `rclone` that they include.