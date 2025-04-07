# Plan for Replacing RMO Functionality in dbatools

## Background
Microsoft has broken RMO (Replication Management Objects) and Replication on Linux. The RMO libraries are no longer compatible with newer versions of .NET Core on Linux, showing errors like "binary format not supported" even though it's x64. We need to replace all replication functionality in dbatools with a solution that works on both Windows and Linux.

## Approach
Create fake/stand-in classes that mimic the original RMO classes but use SQL Server replication stored procedures behind the scenes instead of the actual RMO libraries.

## 1. Analysis Phase

### 1.1 Identify All RMO-Dependent Commands
- Get-DbaReplServer
- Get-DbaReplPublication
- Get-DbaReplArticle
- Get-DbaReplDistributor
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
- Other replication-related commands

### 1.2 Analyze RMO Class Structure
Understand the RMO class hierarchy to create appropriate replacements:
- ReplicationServer
- ReplicationDatabase
- Publication (TransPublication, MergePublication)
- Article (TransArticle, MergeArticle)
- Subscription (TransSubscription, MergeSubscription)

## 2. Design Phase

### 2.1 Create Replacement Class Structure
Design replacement classes that mimic RMO but use T-SQL internally:
- DbaReplServer
- DbaReplDatabase
- DbaReplPublication
- DbaReplArticle
- DbaReplSubscription
- Other necessary classes

### 2.2 Map RMO Methods to T-SQL Stored Procedures
Identify the T-SQL stored procedures that can replace RMO functionality:
- sp_get_distributor
- sp_helppublication
- sp_helparticle
- sp_adddistributor
- sp_dropdistributor
- sp_replicationdboption
- sp_addpublication
- sp_droppublication
- sp_addarticle
- sp_droparticle
- sp_addsubscription
- sp_dropsubscription
- Other replication stored procedures

## 3. Implementation Phase

### 3.1 Create Core Infrastructure
1. Create a new module file for replication replacement classes
2. Implement base connection and utility functions
3. Create mock classes that mimic RMO structure but use T-SQL

### 3.2 Implement Command Replacements
Starting with Get-DbaReplDistributor as suggested:
1. Create DbaReplServer Class
2. Implement sp_get_distributor Call
3. Map Results to Class Properties
4. Test on Windows
5. Test on Linux
6. Move to next command

### 3.3 Implement Remaining Commands
Follow a similar pattern for each command, in order of complexity:
1. Get commands (read-only operations)
2. Enable/Disable commands (configuration operations)
3. Add/New commands (creation operations)
4. Remove commands (deletion operations)
5. Test commands (diagnostic operations)

## 4. Testing Phase

### 4.1 Unit Testing
Create unit tests for each replacement command:
- Test basic functionality
- Test edge cases
- Test error handling
- Test performance

### 4.2 Integration Testing
Test commands working together in common replication scenarios:
- Setup distributor
- Configure publishing
- Create publication
- Add articles
- Create subscription
- Test replication
- Clean up

### 4.3 Cross-Platform Testing
Ensure functionality works on both Windows and Linux:
- Test on Windows
- Test on Linux
- Compare results
- Fix discrepancies

## 5. Documentation and Deployment

### 5.1 Update Documentation
Update help files and examples for all replaced commands.

### 5.2 Create Migration Guide
Document any API changes or behavior differences for users.

## 6. Detailed Implementation Approach

For each command, we'll follow this pattern:
1. Create a replacement class that mimics the RMO class
2. Implement the class methods using T-SQL stored procedures
3. Update the command to use the new class instead of RMO
4. Ensure backward compatibility with existing scripts

For example, for Get-DbaReplDistributor:
```powershell
# Current implementation using RMO
$distributor = Get-DbaReplServer -SqlInstance $instance
# Properties accessed: IsDistributor, DistributionDatabases, etc.

# New implementation using T-SQL
# 1. Create DbaReplServer class that mimics ReplicationServer
# 2. Implement IsDistributor property using sp_get_distributor
# 3. Implement DistributionDatabases property using sp_helpdistributiondb
# 4. Update Get-DbaReplServer to use the new class