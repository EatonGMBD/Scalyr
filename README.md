# Scalyr

<!-- [![Build Status](https://travis-ci.org/)](https://travis-ci.org/) -->

The library lets your Electric Imp Agent code integrate with the [Scalyr](https://www.scalyr.com/) service. It makes use of the [Scalyr REST API](https://www.scalyr.com/help/api)

**To add this library to your project, do one of the following:**
<!-- - add #require "Scalyr.agent.lib.nut:1.0.0" to the top of your agent code. --><!-- //TODO: This will need to be adopted as a proper library by electric imp for this to be an option -->
 - **add the contents of** `Scalyr.agent.lib.nut` ** from the [Releases](./releases) tab to your agent code**
     - _This "**built**" file contains all of the dependencies required by the library, as defined by [`@include once` Builder Directives](https://github.com/electricimp/Builder#include-once)_
 - **use [Builder](https://github.com/electricimp/Builder) and add `@include once "github:deldrid1/Scalyr/Scalyr.agent.lib.nut@v1.0.0"` to you agent code**

## Examples

Working examples with step-by-step instructions are provided in the [Examples](./Examples) directory and described [here](./Examples/README.md).

## About Scalyr

[Scalyr](https://www.scalyr.com/product) is a SaaS offering run in AWS that provides "_blazing-fast log management for engineering and operations teams_".  The nitty gritty of what is behind the service can be found at _[How Scalyr Works](https://www.scalyr.com/help/how-scalyr-works)_.

Scalyr also has a phenomenal [blog](https://blog.scalyr.com/) with [many interesting articles](https://blog.scalyr.com/2014/05/searching-20-gbsec-systems-engineering-before-algorithms/)

Before working with Scalyr, you need to:

- [Create a Scalyr Account](https://www.scalyr.com/signup).
- Obtain a "_Write Logs_" API token. API tokens can be obtained at https://www.scalyr.com/keys.

## Library Usage

//TODO:

## Dependencies
Dependencies are included defined by [`@include once` Builder Directives](https://github.com/electricimp/Builder#include-once)_ within the source code.

## Versioning

This project uses [Semantic Versioning 2.0.0](https://semver.org/).  All releases will be tagged in git and appropriate distribution files saved in GitHub.

Given a version number vMAJOR.MINOR.PATCH, the project will increment the:

- MAJOR version when an incompatible API change is made,
- MINOR version when functionality is added in a backwards-compatible manner
- PATCH version when backwards-compatible bug fixes are made.

Additional labels for pre-release and build metadata may be used as extensions to the MAJOR.MINOR.PATCH format, for example `v1.0.0-rc1`.

## License

The GooglePubSub library is licensed under the [MIT License](./LICENSE)
