# Perfect-FastCGI
FastCGI server for Perfect

Perfect server can run with either its built-in HTTP 1.1 system or with this FastCGI based server.

This server can run with any FastCGI enabled webserver over either UNIX socket files or TCP.

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