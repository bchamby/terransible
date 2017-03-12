provider "aws" {
  region = "${var.aws_region}"
  profile = "${var.aws_profile}"
}

resource "aws_vpc" "vpc" {
  cidr_block = "10.1.0.0/16"
}

resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = "${aws_vpc.vpc.id}"
}

resource "aws_route_table" "public" {
  vpc_id = "${aws_vpc.vpc.id}"
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.internet_gateway.id}"
  }
  tags {
    Name = "public"
  }
}

resource "aws_default_route_table" "private" {
  default_route_table_id = "${aws_vpc.vpc.default_route_table_id}"
  tags {
    Name = "private"
  }
}

resource "aws_subnet" "public" {
  vpc_id = "${aws_vpc.vpc.id}"
  cidr_block = "10.1.1.0/24"
  map_public_ip_on_launch = true
  availability_zone = "us-east-1d"
  tags {
    Name = "public"
  }
}

resource "aws_subnet" "private1" {
  vpc_id = "${aws_vpc.vpc.id}"
  cidr_block = "10.1.2.0/24"
  map_public_ip_on_launch = false
  availability_zone = "us-east-1a"
  tags {
    Name = "private1"
  }
}

resource "aws_subnet" "private2" {
  vpc_id = "${aws_vpc.vpc.id}"
  cidr_block = "10.1.3.0/24"
  map_public_ip_on_launch = false
  availability_zone = "us-east-1c"
  tags {
    Name = "private2"
  }
}

resource "aws_subnet" "rds1" {
  vpc_id = "${aws_vpc.vpc.id}"
  cidr_block = "10.1.4.0/24"
  map_public_ip_on_launch = false
  availability_zone = "us-east-1a"
  tags {
    Name = "rds1"
  }
}

resource "aws_subnet" "rds2" {
  vpc_id = "${aws_vpc.vpc.id}"
  cidr_block = "10.1.5.0/24"
  map_public_ip_on_launch = false
  availability_zone = "us-east-1c"
  tags {
    Name = "rds2"
  }
}

resource "aws_subnet" "rds3" {
  vpc_id = "${aws_vpc.vpc.id}"
  cidr_block = "10.1.6.0/24"
  map_public_ip_on_launch = false
  availability_zone = "us-east-1d"
  tags {
    Name = "rds3"
  }
}

# subnet associations

resource "aws_route_table_association" "public_assoc" {
  subnet_id = "${aws_subnet.public.id}"
  route_table_id = "${aws_route_table.public.id}"
}

resource "aws_route_table_association" "private1_assoc" {
  subnet_id = "${aws_subnet.private1.id}"
  route_table_id = "${aws_route_table.public.id}"
}

resource "aws_route_table_association" "private2_assoc" {
  subnet_id = "${aws_subnet.private2.id}"
  route_table_id = "${aws_route_table.public.id}"
}

resource "aws_db_subnet_group" "rds_subnetgroup" {
  name = "rds_subnetgroup"
  subnet_ids = ["${aws_subnet.rds1.id}", "${aws_subnet.rds2.id}", "${aws_subnet.rds3.id}"]
  tags {
    Name = "rds_sng"
  }
}

resource "aws_security_group" "public" {
  name = "sg_public"
  description = "Used for load balancer."
  vpc_id = "${aws_vpc.vpc.id}"

  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["${var.localip}/32"]
  }

  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "private" {
  name = "sg_private"
  description = "Used for private instances."
  vpc_id = "${aws_vpc.vpc.id}"

# access from other security groups

  ingress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["10.1.0.0/16"]
  }

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "rds" {
  name = "sg_rds"
  description = "Used for DB instances."
  vpc_id = "${aws_vpc.vpc.id}"

  ingress {
    from_port = 3306
    to_port = 3306
    protocol = "tcp"
    security_groups = ["${aws_security_group.public.id}", "${aws_security_group.private.id}"]
  }
}

resource "aws_db_instance" "db" {
  allocated_storage = 10
  engine = "mysql"
  engine_version = "5.6.27"
  instance_class = "${var.db_instance_class}"
  name = "${var.dbname}"
  username = "${var.dbuser}"
  password = "${var.dbpassword}"
  db_subnet_group_name = "${aws_db_subnet_group.rds_subnetgroup.name}"
  vpc_security_group_ids = ["${aws_security_group.rds.id}"]
}

resource "aws_iam_instance_profile" "s3_access" {
  name = "s3_access"
  roles = ["${aws_iam_role.s3_access.name}"]
}

resource "aws_iam_role_policy" "s3_access_policy" {
  name = "s3_access_policy"
  role = "${aws_iam_role.s3_access.id}"
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "s3:*",
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_iam_role" "s3_access" {
  name = "s3_access"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

# Create S3 VPC endpoint
resource "aws_vpc_endpoint" "private-s3" {
  vpc_id = "${aws_vpc.vpc.id}"
  service_name = "com.amazonaws.${var.aws_region}.s3"
  route_table_ids = ["${aws_vpc.vpc.main_route_table_id}", "${aws_route_table.public.id}"]
  policy = <<POLICY
{
  "Statement": [
    {
      "Action": "*",
      "Effect": "Allow",
      "Resource": "*",
      "Principal": "*"
    }
  ]
}
POLICY
}

#S3 code bucket

resource "aws_s3_bucket" "code" {
  bucket = "${var.domain_name}_code1115"
  acl = "private"
  force_destroy = true
  tags {
    Name = "code bucket"
  }
}

resource "aws_key_pair" "auth" {
  key_name = "${var.key_name}"
  public_key = "${file(var.public_key_path)}"
}

# Dev server

resource "aws_instance" "dev" {
  instance_type = "${var.dev_instance_type}"
  ami = "${var.dev_ami}"
  tags {
    Name = "dev"
  }
  key_name = "${aws_key_pair.auth.id}"
  vpc_security_group_ids = ["${aws_security_group.public.id}"]
  iam_instance_profile = "${aws_iam_instance_profile.s3_access.id}"
  subnet_id = "${aws_subnet.public.id}"

  provisioner "local-exec" {
    command = <<EOP
cat <<EOF > aws_hosts
[dev]
${aws_instance.dev.public_ip}
[dev:vars]
s3code=${aws_s3_bucket.code.bucket}
EOF
EOP
  }

  provisioner "local-exec" {
    command = "sleep 360 && ansible-playbook -i aws_hosts wordpress.yml"
  }
}

#load balancer
#AMI
#launch configuration
#ASG

#Route53 records
#primary
#www
#dev
#db CNAME
