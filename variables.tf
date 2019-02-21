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

variable "k8stoken" {}

variable "cluster-name" {
  default = "k8s"
  description = "Controls the naming of the AWS resources"
}

variable "access_key" {
  default = ""
}

variable "secret_key" {
  default = ""
}

variable "k8s-ssh-key" {}

variable "admin-cidr-blocks" {
  description = "A comma separated list of CIDR blocks to allow SSH connections from."
}

variable "region" {
  default = "us-east-1"
}

variable "kubernetes-version" {
  default = "1.13.1"
  description = "Which version of Kubernetes to install"
}

variable "master-instance-type" {
  default = "m1.small"
  description = "Which EC2 instance type to use for the master nodes"
}

variable "master-spot-price" {
  default = "0.01"
  description = "The maximum spot bid for the master node"
}

variable "worker-instance-type" {
  default = "m1.small"
  description = "Which EC2 instance type to use for the worker nodes"
}

variable "worker-spot-price" {
  default = "0.01"
  description = "The maximum spot bid for worker nodes"
}

variable "min-worker-count" {
  default = "1"
  description = "The minimum worker node count"
}

variable "max-worker-count" {
  default = "1"
  description = "The maximum worker node count"
}

variable "backup-enabled" {
  default = "1"
  description = "Whether or not the automatic S3 backup should be enabled. (1 for enabled, 0 for disabled)"
}

variable "backup-cron-expression" {
  default = "*/15 * * * *"
  description = "A cron expression to use for the automatic etcd backups."
}

variable "external-dns-enabled" {
  default = "1"
  description = "Whether or not to enable external-dns. (1 for enabled, 0 for disabled)"
}

variable "nginx-ingress-enabled" {
  default = "1"
  description = "Whether or not to enable nginx ingress. (1 for enabled, 0 for disabled)"
}

variable "nginx-ingress-domain" {
  default = ""
  description = "The DNS name to map to Nginx Ingress (using External DNS)"
}

variable "cert-manager-enabled" {
  default = "1"
  description = "Whether or not to enable the cert manager. (1 for enabled, 0 for disabled)"
}

variable "cert-manager-email" {
  default = ""
  description = "The email address to use for Let's Encrypt certificate requests"
}

variable "cluster-autoscaler-enabled" {
  default = "0"
  description = "Whether or not to enable the cluster autoscaler. (1 for enabled, 0 for disabled)"
}
