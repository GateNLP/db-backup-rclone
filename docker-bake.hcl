variable "DBBR_REGISTRY" {
  default = ""
}

variable VERSION_RCLONE {
  default = "v1.75.2"
}

variable TAGS {
  default = ["latest", "rclone-${VERSION_RCLONE}"]
  type = list(string)
}

variable PROD {
  default = false
}

target "_dev" {
}

target "_prod" {
  platforms = ["linux/amd64", "linux/arm64"]
}

target "default" {
  inherits = [PROD ? "_prod" : "_dev"]
  context = "."
  dockerfile = "Dockerfile"
  matrix = {
    db = [
      {
        kind = "postgresql"
        ver = "16"
        tails = ["-pg16"]
      },
      {
        kind = "postgresql"
        ver = "17"
        tails = ["-pg17"]
      },
      {
        kind = "postgresql"
        ver = "18"
        tails = ["-pg18", ""]
      },
      {
        kind = "mariadb"
        ver = ""
        tails = [""]
      }
    ]
  }
  name = "${db.kind}${db.ver}"
  target = db.kind
  tags = flatten([for tag in TAGS: [for tail in db.tails: "${DBBR_REGISTRY}${db.kind}-backup-rclone:${tag}${tail}"]])
  args = {
    VERSION_RCLONE = VERSION_RCLONE
    VERSION_DB = db.ver
  }
}
