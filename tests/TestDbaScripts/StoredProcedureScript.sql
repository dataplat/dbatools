CREATE PROCEDURE dbo.TestProc1
AS
BEGIN
    SELECT 1 AS TestResults
END
GO

CREATE PROCEDURE [dbo].[TestProc2]
(
    @Parameter1 INT,
    @Parameter2 nvarchar(5)
)
AS
BEGIN
    SELECT 1 AS TestResults FROM Person.Person
END
GO

DROP PROCEDURE dbo.TestProc2
GO

CREATE PROCEDURE dbo.TestProc3
(
    @Parameter1 INT,
    @Parameter2 nvarchar(5)
)
WITH RECOMPILE
AS
BEGIN
    SELECT 1 AS TestResults FROM Person.Person
END
GO