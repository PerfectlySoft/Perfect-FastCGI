# Perfect-FastCGI
FastCGI server for Perfect

[![GitHub version](https://badge.fury.io/gh/PerfectlySoft%2FPerfect-FastCGI.svg)](https://badge.fury.io/gh/PerfectlySoft%2FPerfect-FastCGI) 
[![Gitter](https://badges.gitter.im/PerfectlySoft/PerfectDocs.svg)](https://gitter.im/PerfectlySoft/PerfectDocs?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge)

Perfect server can run with either its built-in HTTP 1.1 system or with this FastCGI based server.

This server can run with any FastCGI enabled webserver over either UNIX socket files or TCP.

## Issues

We are transitioning to using JIRA for all bugs and support related issues, therefore the GitHub issues has been disabled.

If you find a mistake, bug, or any other helpful suggestion you'd like to make on the docs please head over to [http://jira.perfect.org:8080/servicedesk/customer/portal/1](http://jira.perfect.org:8080/servicedesk/customer/portal/1) and raise it.

A comprehensive list of open issues can be found at [http://jira.perfect.org:8080/projects/ISS/issues](http://jira.perfect.org:8080/projects/ISS/issues)


## Apache 24
To run with Apache 2.4, build and install the mod_perfect FastCGI module:

[Perfect-FastCGI-Apache2.4](https://github.com/PerfectlySoft/Perfect-FastCGI-Apache2.4)

## NGINX
Instructions for running with NGINX:

[NGINX](https://github.com/PerfectlySoft/Perfect/wiki/NGINX)

## Starter Template
Get started with a FastCGI based project template:

[PerfectTemplateFCGI](https://github.com/PerfectlySoft/PerfectTemplateFCGI)

## Building

Add this package as a dependency:

```swift
.Package(url:"https://github.com/PerfectlySoft/Perfect-FastCGI.git", versions: Version(0,0,0)..<Version(10,0,0))
```
