# RMO Replacement for dbatools

## Overview

This implementation replaces the Microsoft Replication Management Objects (RMO) functionality in dbatools with a custom implementation that uses T-SQL stored procedures instead of the RMO libraries. This is necessary because Microsoft has broken RMO and Replication on Linux, making it incompatible with newer versions of .NET Core.

## Implementation Details

### Approach

The implementation creates fake/stand-in classes that mimic the original RMO classes but use SQL Server replication stored procedures behind the scenes. This allows the existing dbatools commands to continue working without requiring changes to their API.

### Files Created/Modified

1. **New Files:**
   - `private/functions/DbaReplicationClasses.ps1`: Contains the replacement classes for RMO
   - `private/functions/Add-DbaReplicationLibrary.ps1`: Loads the replacement classes
   - `RMO_Replacement_Plan.md`: The plan for implementing the replacement
   - `RMO_Replacement_README.md`: This file

2. **Modified Files:**
   - `public/Get-DbaReplServer.ps1`: Updated to use the replacement classes
   - `public/Get-DbaReplDistributor.ps1`: Updated to use the replacement classes

3. **Test Files:**
   - `tests/Get-DbaReplDistributor.Tests.ps1`: Tests for the updated Get-DbaReplDistributor command

### Classes Implemented

1. **DbaReplObject**: Base class for all replication objects
2. **DbaReplServer**: Replacement for Microsoft.SqlServer.Replication.ReplicationServer
3. **DbaReplDistributionDatabase**: Replacement for Microsoft.SqlServer.Replication.DistributionDatabase
4. **DbaReplDatabase**: Replacement for Microsoft.SqlServer.Replication.ReplicationDatabase
5. **DbaReplPublication**: Replacement for Microsoft.SqlServer.Replication.Publication
6. **DbaReplArticle**: Replacement for Microsoft.SqlServer.Replication.Article
7. **DbaReplSubscription**: Replacement for Microsoft.SqlServer.Replication.Subscription

## Usage

The usage of the replication commands remains the same as before. The changes are transparent to the end user.

```powershell
# Get replication server information
Get-DbaReplServer -SqlInstance sql2016

# Get distributor information
Get-DbaReplDistributor -SqlInstance sql2016
```

## Limitations

1. Some advanced RMO functionality might not be fully implemented yet.
2. Performance might differ slightly from the original RMO implementation.

## Next Steps

1. Implement the remaining replication commands:
   - Get-DbaReplPublication
   - Get-DbaReplArticle
   - Enable-DbaReplPublishing
   - Enable-DbaReplDistributor
   - Disable-DbaReplPublishing
   - Disable-DbaReplDistributor
   - Add-DbaReplArticle
   - Remove-DbaReplArticle
   - New-DbaReplPublication
   - Remove-DbaReplPublication
   - New-DbaReplSubscription
   - Remove-DbaReplSubscription
   - Test-DbaReplLatency
   - Export-DbaReplServerSetting

2. Add more comprehensive tests for all implemented commands.

3. Update documentation to reflect the changes.

## Contributing

If you find any issues or have suggestions for improvements, please submit an issue or pull request on GitHub.