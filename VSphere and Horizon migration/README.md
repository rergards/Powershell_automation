# VMware Horizon VM Migration Scripts

## Overview

This repository contains PowerShell scripts for automating the migration of VMs in VMware Horizon environments. It includes a main migration script and a module for handling batch migrations of Horizon pools.

## Prerequisites

- VMware PowerCLI
- Horizon module
- CSV file with details of VMs to be migrated

## Usage

- **MainMigrationScript.ps1**: This script migrates VMs based on a CSV file. Configure the variables in the script to match your environment.
- **MigrateHorizonPoolBatchModule.ps1**: This module provides functions to handle batch migrations in Horizon. Import this module in your PowerShell session before running the main script.

To use these scripts, update the placeholders with your specific environment details and ensure all prerequisites are met.

### Example

```powershell
.\MainMigrationScript.ps1
```
