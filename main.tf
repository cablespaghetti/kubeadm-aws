
/*
Copyright (c) 2016, UPMC Enterprises
All rights reserved.
Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:
    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name UPMC Enterprises nor the
      names of its contributors may be used to endorse or promote products
      derived from this software without specific prior written permission.
THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL UPMC ENTERPRISES BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PR)
OCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
*/

provider "aws" {
  version    = "~> 1.48"
  access_key = "${var.access_key}"
  secret_key = "${var.secret_key}"
  region     = "${var.region}"
}

provider "template" {
  version    = "1.0.0"
}

provider "random" {
  version    = "2.0.0"
}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  enable_dns_hostnames = true

  tags {
    Name = "${var.cluster-name}"
    Environment = "${var.cluster-name}"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = "${aws_vpc.main.id}"

  tags {
    Name = "${var.cluster-name}"
    Environment = "${var.cluster-name}"
  }
}

resource "aws_route_table" "r" {
  vpc_id = "${aws_vpc.main.id}"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.gw.id}"
  }

  depends_on = ["aws_internet_gateway.gw"]

  tags {
    Name = "${var.cluster-name}"
    Environment = "${var.cluster-name}"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id = "${aws_subnet.public.id}"
  route_table_id = "${aws_route_table.r.id}"
}

resource "aws_subnet" "public" {
  vpc_id = "${aws_vpc.main.id}"
  cidr_block = "10.0.100.0/24"
  availability_zone = "${var.region}${var.az}"
  map_public_ip_on_launch = true

  tags {
    Name = "${var.cluster-name}"
    Environment = "${var.cluster-name}"
  }
}

resource "aws_security_group" "kubernetes" {
  name = "${var.cluster-name}"
  description = "Allow inbound ssh traffic"
  vpc_id = "${aws_vpc.main.id}"

  tags {
    Name = "${var.cluster-name}"
    Environment = "${var.cluster-name}"
  }
}

resource "aws_security_group_rule" "allow_all_from_self" {
  type            = "ingress"
  from_port       = 0
  to_port         = 0
  protocol        = "-1"
  source_security_group_id = "${aws_security_group.kubernetes.id}"

  security_group_id = "${aws_security_group.kubernetes.id}"
}

resource "aws_security_group_rule" "allow_ssh_from_admin" {
  type            = "ingress"
  from_port       = 22
  to_port         = 22
  protocol        = "tcp"
  cidr_blocks     = "${split(",", var.admin-cidr-blocks)}"

  security_group_id = "${aws_security_group.kubernetes.id}"
}

resource "aws_security_group_rule" "allow_k8s_from_admin" {
  type            = "ingress"
  from_port       = 6443
  to_port         = 6443
  protocol        = "tcp"
  cidr_blocks     = "${split(",", var.admin-cidr-blocks)}"

  security_group_id = "${aws_security_group.kubernetes.id}"
}

resource "aws_security_group_rule" "allow_https_from_web" {
  type            = "ingress"
  from_port       = 443
  to_port         = 443
  protocol        = "tcp"
  cidr_blocks     = ["0.0.0.0/0"]

  security_group_id = "${aws_security_group.kubernetes.id}"
}

resource "aws_security_group_rule" "allow_http_from_web" {
  type            = "ingress"
  from_port       = 80
  to_port         = 80
  protocol        = "tcp"
  cidr_blocks     = ["0.0.0.0/0"]

  security_group_id = "${aws_security_group.kubernetes.id}"
}

resource "aws_security_group_rule" "allow_all_out" {
  type            = "egress"
  from_port       = 0
  to_port         = 0
  protocol        = "-1"
  cidr_blocks     = ["0.0.0.0/0"]

  security_group_id = "${aws_security_group.kubernetes.id}"
}

resource "aws_s3_bucket" "s3-bucket" {
  bucket_prefix   = "${var.cluster-name}"
  force_destroy   = "true"

  versioning {
    enabled = "${var.versioned-bucket}"
  }

  lifecycle_rule {
    enabled = true
    id      = "bucket"
    prefix  = ""
    abort_incomplete_multipart_upload_days = 1

    noncurrent_version_expiration {
      days = 7
    }
  }

  tags {
    Environment = "${var.cluster-name}"
  }
}

resource "aws_s3_bucket_object" "external-dns-manifest" {
  count  = "${var.external-dns-enabled}"
  bucket = "${aws_s3_bucket.s3-bucket.id}"
  key    = "manifests/external-dns.yaml"
  source = "manifests/external-dns.yaml"
  etag   = "${md5(file("manifests/external-dns.yaml"))}"
}

resource "aws_s3_bucket_object" "ebs-storage-class-manifest" {
  bucket = "${aws_s3_bucket.s3-bucket.id}"
  key    = "manifests/ebs-storage-class.yaml"
  source = "manifests/ebs-storage-class.yaml"
  etag   = "${md5(file("manifests/ebs-storage-class.yaml"))}"
}

resource "aws_s3_bucket_object" "nginx-ingress-manifest" {
  count  = "${var.nginx-ingress-enabled}"
  bucket = "${aws_s3_bucket.s3-bucket.id}"
  key    = "manifests/nginx-ingress-mandatory.yaml"
  source = "manifests/nginx-ingress-mandatory.yaml"
  etag   = "${md5(file("manifests/nginx-ingress-mandatory.yaml"))}"
}

data "template_file" "nginx-ingress-nodeport-manifest" {
  count  = "${var.nginx-ingress-enabled}"
  template = "${file("manifests/nginx-ingress-nodeport.yaml.tmpl")}"
  vars {
    nginx_ingress_domain = "${var.nginx-ingress-domain}"
  }
}
resource "aws_s3_bucket_object" "nginx-ingress-nodeport-manifest" {
  count  = "${var.nginx-ingress-enabled}"
  bucket = "${aws_s3_bucket.s3-bucket.id}"
  key    = "manifests/nginx-ingress-nodeport.yaml"
  content = "${data.template_file.nginx-ingress-nodeport-manifest.rendered}"
  etag   = "${md5(data.template_file.nginx-ingress-nodeport-manifest.rendered)}"
}

data "template_file" "cluster-autoscaler-manifest" {
  template = "${file("manifests/cluster-autoscaler-autodiscover.yaml.tmpl")}"
  vars {
    cluster_name = "${var.cluster-name}"
    cluster_region = "${var.region}"
  }
}
resource "aws_s3_bucket_object" "cluster-autoscaler-manifest" {
  count  = "${var.cluster-autoscaler-enabled}"
  bucket = "${aws_s3_bucket.s3-bucket.id}"
  key    = "manifests/cluster-autoscaler-autodiscover.yaml"
  content = "${data.template_file.cluster-autoscaler-manifest.rendered}"
  etag   = "${md5(data.template_file.cluster-autoscaler-manifest.rendered)}"
}

data "template_file" "cert-manager-issuer-manifest" {
  template = "${file("manifests/cert-manager-issuer.yaml.tmpl")}"
  vars {
    cert_manager_email = "${var.cert-manager-email}"
  }
}
resource "aws_s3_bucket_object" "cert-manager-issuer-manifest" {
  count  = "${var.cert-manager-enabled}"
  bucket = "${aws_s3_bucket.s3-bucket.id}"
  key    = "manifests/cert-manager-issuer.yaml"
  content = "${data.template_file.cert-manager-issuer-manifest.rendered}"
  etag   = "${md5(data.template_file.cert-manager-issuer-manifest.rendered)}"
}

data "template_file" "master-userdata" {
  template = "${file("master.sh")}"

  vars {
    k8stoken = "${local.k8stoken}"
    clustername = "${var.cluster-name}"
    s3bucket = "${aws_s3_bucket.s3-bucket.id}"
    backupcron = "${var.backup-cron-expression}"
    k8sversion = "${var.kubernetes-version}"
    backupenabled = "${var.backup-enabled}"
    certmanagerenabled = "${var.cert-manager-enabled}"
  }
}

data "template_file" "worker-userdata" {
  template = "${file("worker.sh")}"

  vars {
    k8stoken = "${local.k8stoken}"
    masterIP = "10.0.100.4"
    k8sversion = "${var.kubernetes-version}"
  }
}

data "aws_ami" "latest_ami" {
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-instance/ubuntu-bionic-18.04-amd64-server-*"]
  }

  most_recent = true
  owners      = ["099720109477"] # Ubuntu
}

resource "aws_iam_role" "role" {
  name = "${var.cluster-name}-instance-role"
  path = "/"

  assume_role_policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": "sts:AssumeRole",
            "Principal": {
               "Service": "ec2.amazonaws.com"
            },
            "Effect": "Allow"
        }
    ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "policy" {
  role       = "${aws_iam_role.role.name}"
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_policy" "cluster-policy" {
  name        = "${var.cluster-name}-cluster-policy"
  path        = "/"
  description = "Policy for ${var.cluster-name} cluster to allow dynamic provisioning of EBS persistent volumes"

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ec2:AttachVolume",
                "ec2:CreateVolume",
                "ec2:DeleteVolume",
                "ec2:DescribeInstances",
                "ec2:DescribeRouteTables",
                "ec2:DescribeSecurityGroups",
                "ec2:DescribeSubnets",
                "ec2:DescribeVolumes",
                "ec2:DescribeVolumesModifications",
                "ec2:DescribeVpcs",
                "elasticloadbalancing:DescribeLoadBalancers",
                "ec2:DetachVolume",
                "ec2:ModifyVolume",
                "ec2:CreateTags"
            ],
            "Resource": "*"
        }
    ]
}
EOF
}

resource "aws_iam_policy" "autoscaling" {
  count       = "${var.cluster-autoscaler-enabled}"
  name        = "${var.cluster-name}-autoscaling-policy"
  path        = "/"
  description = "Policy for ${var.cluster-name} cluster to allow cluster autoscaling to work"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "autoscaling:DescribeAutoScalingGroups",
        "autoscaling:DescribeAutoScalingInstances",
        "autoscaling:DescribeLaunchConfigurations",
        "autoscaling:DescribeTags",
        "autoscaling:SetDesiredCapacity",
        "autoscaling:TerminateInstanceInAutoScalingGroup"
      ],
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "autoscaling" {
  count      = "${var.cluster-autoscaler-enabled}"
  role       = "${aws_iam_role.role.name}"
  policy_arn = "${aws_iam_policy.autoscaling.arn}"
}

resource "aws_iam_role_policy_attachment" "cluster-policy" {
  role       = "${aws_iam_role.role.name}"
  policy_arn = "${aws_iam_policy.cluster-policy.arn}"
}

resource "aws_iam_policy" "s3-bucket-policy" {
  name        = "${var.cluster-name}-s3-bucket-policy"
  path        = "/"
  description = "Polcy for ${var.cluster-name} cluster to allow access to the Backup S3 Bucket"

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": ["s3:ListBucket"],
            "Resource": ["${aws_s3_bucket.s3-bucket.arn}"]
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:PutObject",
                "s3:GetObject",
                "s3:ListObjects"
            ],
            "Resource": ["${aws_s3_bucket.s3-bucket.arn}/*"]
        }
    ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "s3-bucket-policy" {
  role       = "${aws_iam_role.role.name}"
  policy_arn = "${aws_iam_policy.s3-bucket-policy.arn}"
}

resource "aws_iam_policy" "route53-policy" {
  count       = "${var.external-dns-enabled}"
  name        = "${var.cluster-name}-route53-policy"
  path        = "/"
  description = "Polcy for ${var.cluster-name} cluster to allow access to Route 53 for DNS record creation"

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": ["route53:*"],
            "Resource": "*"
        }
    ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "route53-policy" {
  count      = "${var.external-dns-enabled}"
  role       = "${aws_iam_role.role.name}"
  policy_arn = "${aws_iam_policy.route53-policy.arn}"
}

resource "aws_iam_instance_profile" "profile" {
  name = "${var.cluster-name}-instance-profile"
  role = "${aws_iam_role.role.name}"
}

resource "aws_spot_instance_request" "master" {
  ami           = "${data.aws_ami.latest_ami.id}"
  instance_type = "${var.master-instance-type}"
  subnet_id = "${aws_subnet.public.id}"
  user_data = "${data.template_file.master-userdata.rendered}"
  key_name = "${var.k8s-ssh-key}"
  iam_instance_profile   = "${aws_iam_instance_profile.profile.name}"
  vpc_security_group_ids = ["${aws_security_group.kubernetes.id}"]
  spot_price = "${var.master-spot-price}"
  valid_until = "9999-12-25T12:00:00Z"
  wait_for_fulfillment = true
  private_ip = "10.0.100.4"

  depends_on = ["aws_internet_gateway.gw"]

  tags {
    Name = "${var.cluster-name}-master"
    Environment = "${var.cluster-name}"
  }

  lifecycle {
    ignore_changes = [
      "ami"
    ]
  }
}

# Spot ASG for workers
resource "aws_launch_template" "worker" {
  iam_instance_profile        = { name = "${aws_iam_instance_profile.profile.name}" }
  image_id                    = "${data.aws_ami.latest_ami.id}"
  name                        = "${var.cluster-name}-worker"
  vpc_security_group_ids      = ["${aws_security_group.kubernetes.id}"]
  key_name                    = "${var.k8s-ssh-key}"
  instance_type               = "${var.worker-instance-type}"
  user_data                   = "${base64encode(data.template_file.worker-userdata.rendered)}"
  ebs_optimized               = false
  instance_market_options {
    market_type = "spot"
    spot_options {
      max_price = "${var.worker-spot-price}"
    }
  }
}

resource "aws_autoscaling_group" "worker" {
  max_size             = "${var.max-worker-count}"
  min_size             = "${var.min-worker-count}"
  name                 = "${var.cluster-name}-worker"
  vpc_zone_identifier  = ["${aws_subnet.public.id}"]

  launch_template {
    id = "${aws_launch_template.worker.id}"
    version = "$$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.cluster-name}-worker"
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = "${var.cluster-name}"
    propagate_at_launch = true
  }

  tag {
    key                 = "kubernetes.io/cluster/${var.cluster-name}"
    value               = "owned"
    propagate_at_launch = true
  }

  tag {
    key                 = "k8s.io/cluster-autoscaler/enabled"
    value               = "true"
    propagate_at_launch = true
  }
}
