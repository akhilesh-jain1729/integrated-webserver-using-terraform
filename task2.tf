provider "aws" {
  region                  = "ap-south-1"
  profile                 = "akhil"
}
resource "tls_private_key" "keypair" {
  algorithm   = "RSA"
}
resource "local_file" "privatekey" {
    content     = tls_private_key.keypair.private_key_pem
    filename = "key1.pem"
}
resource "aws_key_pair" "deployer" {
  key_name   = "key1.pem"
  public_key = tls_private_key.keypair.public_key_openssh
}
resource "aws_default_vpc" "default" {
  tags = {
    Name = "Default VPC"
  }
}
resource "aws_default_subnet" "default_az1" {
  availability_zone = "ap-south-1a"

  tags = {
    Name = "Default subnet "
  }
}

resource "aws_security_group" "secure" {
  name        = "secure"
  description = "Allow HTTP, SSH inbound traffic"
  vpc_id      = aws_default_vpc.default.id

  ingress {
    description = "http"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "ssh"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
  from_port   = 0
  to_port     = 0
  protocol    = "-1"
  cidr_blocks = ["0.0.0.0/0"]
}

  tags = {
    Name = "security-wizard"
  }
}

resource "aws_instance" "job2" {
  ami           = "ami-0447a12f28fddb066"
  instance_type = "t2.micro"
  key_name = "key1.pem"
  security_groups = [ "${aws_security_group.secure.name}" ]
  tags = {
    Name = "task2"
  }

  connection {
  type = "ssh"
  user = "ec2-user"
  host = aws_instance.job2.public_ip
  private_key = "${tls_private_key.keypair.private_key_pem}"
  }
  provisioner "remote-exec" {
    inline = [
      "sudo yum update -y",
      "sudo yum install httpd php git nfs-utils amazon-efs-utils -y",
      "sudo systemctl start httpd",
      "sudo systemctl enable httpd",
    ]}}
resource "aws_efs_file_system" "efs" {
  creation_token = "efs-mount"

  tags = {
    Name = "efsmount"
  }
}
resource "aws_efs_mount_target" "alpha" {
  file_system_id = "${aws_efs_file_system.efs.id}"
  subnet_id = "${aws_default_subnet.default_az1.id}"
}

resource "null_resource" "nulllocal2"  {
	provisioner "local-exec" {
	command = "echo  ${aws_instance.job2.public_ip} > publicip.txt"
  	}
}

resource "null_resource" "nullremote3"  {
depends_on = [
    aws_efs_mount_target.alpha,
  ]
  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = "${tls_private_key.keypair.private_key_pem}"
    host     = aws_instance.job2.public_ip
  }

 provisioner "remote-exec" {
    inline = [
      "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/akhilesh-jain1729/integrated-webserver-using-terraform.git /var/www/html",
      "sudo mkdir /efs-mount-point",
      "sudo mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2 ${aws_efs_file_system.efs.id}.efs.ap-south-1.amazonaws.com:/ /efs-mount-point",
      "sudo cd /efs-mount-point",
      "sudo chmod go+rw",
      "sudo mkdir webserver-data",
      "sudo mount webserver-data /var/www/html",
    ]
  }
}

resource "aws_s3_bucket" "bucket-second-task" {
  bucket = "bucket-for-webserver"
  acl    = "private"
  versioning {
    enabled = true
  }

  object_lock_configuration {
    object_lock_enabled = "Enabled"
  }
  force_destroy = true
}
resource "aws_s3_bucket_object" "image-upload" {
  bucket = "bucket-for-webserver"
  key    = "first-img.jpg"
  source = "skillset.jpg"
  acl = "public-read"
  force_destroy = true
}
resource "aws_s3_bucket_public_access_block" "access" {
  bucket = "${aws_s3_bucket.bucket-second-task.id}"

  block_public_acls   = false
  block_public_policy = false
}
resource "aws_cloudfront_origin_access_identity" "origin_access_identity" {
  comment = "cloudfront for bucket"
}

resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
       domain_name = "${aws_s3_bucket.bucket-second-task.bucket_regional_domain_name}"
       origin_id   = "S3-${aws_s3_bucket.bucket-second-task.bucket}"
  s3_origin_config {
      origin_access_identity = "${aws_cloudfront_origin_access_identity.origin_access_identity.cloudfront_access_identity_path}"
                   }
         }  
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
    
    default_cache_behavior {
   allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
   cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${aws_s3_bucket.bucket-second-task.bucket}"

   forwarded_values {
      query_string = false
      cookies {
       forward = "none"
   }
   }
   viewer_protocol_policy = "allow-all"
   min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }
  restrictions {
  geo_restriction {
      restriction_type = "none"
                  }
                }
  viewer_certificate {
    cloudfront_default_certificate = true
                       }
   connection {
  type = "ssh"
  user = "ec2-user"
  host = aws_instance.job2.public_ip
  port = 22
  private_key = "${tls_private_key.keypair.private_key_pem}"
  }
}
resource "null_resource" "nulllocal1"  {
depends_on = [
    null_resource.nullremote3,
  ]
	provisioner "local-exec" {
	    command = "chrome  ${aws_instance.job2.public_ip}"
  	}
}