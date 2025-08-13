variable "DBBR_REGISTRY" {
  default = ""
}

variable VERSION_RCLONE {
  default = "v1.70.3"
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
    db = ["postgresql", "mariadb"]
  }
  name = db
  target = db
  tags = [for tag in TAGS: "${DBBR_REGISTRY}${db}-backup-rclone:${tag}"]
  args = {
    VERSION_RCLONE = VERSION_RCLONE
  }
}
