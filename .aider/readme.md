# Aider Folder

This folder contains configuration and script files for the Aider tool, which is used for automating various tasks within the project.

## Folder Structure

- `.aider/`
  - `.env`: Environment variables for Aider.
  - `aider.psm1`: PowerShell module containing functions for Aider.
  - `prompts/`: Directory containing prompt files used by Aider.

## Configuration Files

- `.aider.conf.yml`: Main configuration file for Aider. It includes settings for linting, testing, and other behaviors.

## PowerShell Module

- `aider.psm1`: This module contains functions such as `Repair-ParameterTest` and `Repair-Error` which are used to automate error fixing and parameter testing.

## Prompts

- `prompts/`: This directory contains markdown files used as prompts for Aider. Examples include `fix-errors.md` and `conventions.md`.

## Environment Files

- `.env`: Contains environment variables specific to Aider.
- `.env.example`: Example environment variables file to be used as a template.

## Usage

To use Aider, ensure that the necessary environment variables are set up in the `.env` file. You can use the `.env.example` file as a template. The PowerShell module `aider.psm1` provides various functions to automate tasks such as error fixing and parameter testing.

