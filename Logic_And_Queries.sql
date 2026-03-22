-----------------------------------------------------------------------------------------
-- DATABASE OPERATIONS: DREAMDRESS PROJECT
-----------------------------------------------------------------------------------------

-----------------------------------------------------------------------------------------
-- TRIGGER SECTION
-----------------------------------------------------------------------------------------

--- Trigger: AssignSeamstress
--- Event: After an insert into the [fixes] (Alterations) table.
--- Description: This trigger automatically categorizes the alteration type and 
--- assigns the most suitable seamstress based on their skill and current workload.

CREATE TRIGGER [dbo].[matchDm] ON [dbo].[fixes] AFTER INSERT AS
BEGIN
    DECLARE @des VARCHAR(100), @fixid SMALLINT, @sk VARCHAR(30)
    SELECT @des = [describe], @fixid = [fixId] FROM inserted 

    -- 1. Check alteration description and set the complexity type accordingly:
    -- Additions and Zippers -> 'Complex'
    -- Hemming only -> 'Simple'
    -- All types of narrowing -> 'Standard'
    
    IF (@des LIKE N'%תוספת%' OR @des LIKE N'%רוכסן%')
    BEGIN
        UPDATE fixes SET [typeFix] = 'Complex' WHERE [fixId] = @fixid
        SET @sk = 'Complex'
    END
    ELSE IF (@des LIKE N'%הצרה%')
    BEGIN
        UPDATE fixes SET [typeFix] = 'Standard' WHERE [fixId] = @fixid
        SET @sk = 'Standard'
    END
    ELSE IF (@des LIKE N'מכפלת%')
    BEGIN
        UPDATE fixes SET [typeFix] = 'Simple' WHERE [fixId] = @fixid
        SET @sk = 'Simple'
    END
    ELSE
    BEGIN
        -- Rollback if the description does not match required keywords
        PRINT 'Error: Please enter a valid description (Hem, Narrowing, Addition, Zipper)'
        ROLLBACK
        RETURN
    END

    -- 2. Find and assign the best-suited seamstress:
    -- Selects the first seamstress whose skill matches the complexity 
    -- and has the lowest number of current assignments.
    
    DECLARE @dm SMALLINT 
    SELECT @dm = (
        SELECT [DmId] FROM   
        (
            SELECT TOP(1) [dbo].[DressMakers].[DmId], COUNT([fixId]) AS 'Workload' 
            FROM [dbo].[fixes] RIGHT JOIN [dbo].[DressMakers]
            ON DressMakers.DmId = [dbo].[fixes].[DmId]
            WHERE [DmSkill] = @sk 
            GROUP BY [dbo].[DressMakers].[DmId] 
            ORDER BY 'Workload' ASC
        ) AS q1
    )

    UPDATE fixes SET [DmId] = @dm WHERE [fixId] = @fixid
    -- Seamstress assignment completed.
END 
GO

-----------------------------------------------------------------------------------------
-- STORED PROCEDURES SECTION
-----------------------------------------------------------------------------------------

------------ PROCEDURE 1: updateTurns
-- Description: Generates future appointment slots and cleans up old records.
-- 1. Deletes appointments older than one week.
-- 2. Generates new slots for the next two months (unless a different date is specified).

ALTER PROCEDURE updateTurns(@date DATE) AS
BEGIN 
    -- Remove outdated appointments
    DELETE FROM turns WHERE [date] < DATEADD(DAY, -7, GETDATE())

    DECLARE @d DATE
    -- Start generating from the day after the last existing appointment
    SET @d = DATEADD(DAY, 1, (SELECT TOP 1 [date] FROM [dbo].[turns] ORDER BY [date] DESC))
    
    -- If table is empty, start from today
    IF (@d IS NULL) SET @d = GETDATE()
    
    DECLARE @m TIME
    -- Default timeframe: 2 months from today
    IF @date IS NULL SET @date = DATEADD(MONTH, 2, GETDATE())

    WHILE (@d < @date)
    BEGIN
        -- Business hours: 08:30 to 16:00
        SET @m = '08:30:00'
        WHILE (@m < '16:00:00')
        BEGIN
            -- Insert 30-minute slots
            INSERT INTO [dbo].[turns]([date], [time]) VALUES (@d, @m)
            SET @m = DATEADD(MINUTE, 30, @m)
        END
        
        SET @d = DATEADD(DAY, 1, @d)
        -- Salon closed on Friday and Saturday
        IF (DATEPART(DW, @d) = 6) SET @d = DATEADD(DAY, 2, @d)
    END
    
    -- Reset Identity for clean IDs
    DBCC CHECKIDENT([turns], RESEED, 0)
END
GO

------------ PROCEDURE 2: taketurn
-- Description: Assigns a "Pickup Appointment" for the bride.
-- Starting one week before the wedding, the first available slot is assigned to the bride.

ALTER PROCEDURE taketurn(@brideid SMALLINT) AS
BEGIN
    DECLARE @date DATE
    DECLARE @turnId SMALLINT
    
    SELECT @date = [DateEven] FROM [dbo].[BridesDetails] WHERE [BrideId] = @brideid 
    SET @date = DATEADD(DAY, -7, @date)

    -- Check if the target date exists in the appointments table
    IF (@date > (SELECT TOP 1 [date] FROM [dbo].[turns] ORDER BY [date] DESC))
    BEGIN 
        -- Generate appointments up to the required date if missing
        EXEC updateTurns @date
    END

    -- Find the first available slot on or after the target date
    SET @turnId = (SELECT TOP 1 [TurnId] FROM [dbo].[turns] WHERE [date] >= @date AND brideId IS NULL)

    -- Assign the bride to the slot and mark it as 'Pickup'
    UPDATE [dbo].[turns] SET [brideId] = @brideid WHERE [TurnId] = @turnId
    UPDATE [dbo].[turns] SET [type] = 'Pickup' WHERE [TurnId] = @turnId
END
GO

-----------------------------------------------------------------------------------------
-- CURSOR SECTION
-----------------------------------------------------------------------------------------

-- Cursor Description: Updates pickup appointments for all brides who don't have one scheduled yet.
DECLARE @brideid SMALLINT  
DECLARE crs CURSOR FOR 
    SELECT [BrideId] FROM [dbo].[BridesDetails] 
    WHERE [brideId] NOT IN (SELECT [brideId] FROM [dbo].[turns] WHERE [type] = 'Pickup')

OPEN crs
FETCH NEXT FROM crs INTO @brideid
WHILE @@FETCH_STATUS = 0
BEGIN
    -- Call the taketurn procedure for each bride
    EXEC taketurn @brideid 
    FETCH NEXT FROM crs INTO @brideid
END
CLOSE crs
DEALLOCATE crs
GO

-----------------------------------------------------------------------------------------
-- FUNCTIONS SECTION
-----------------------------------------------------------------------------------------

--------------- Scalar Function: gain
-- Description: Calculates total revenue for a specific month based on dresses taken during that period.

ALTER FUNCTION [dbo].[gain](@month SMALLINT) RETURNS VARCHAR(100) AS
BEGIN
    DECLARE @sum INT
    -- Sum of dress prices for weddings occurring in the specified month
    SET @sum = (
        SELECT SUM([DressPrice]) FROM [dbo].[Dresses] 
        JOIN [dbo].[orders] ON [dbo].[orders].[DressId] = [dbo].[Dresses].[DressId]
        JOIN [dbo].[BridesDetails] ON [dbo].[BridesDetails].BrideId = [dbo].[orders].BrideId
        WHERE MONTH([DateEven]) = @month
    ) 
 
    IF (@sum IS NULL) -- Case: No revenue recorded
    BEGIN
        RETURN 'No revenue recorded for ' + DATENAME(MONTH, DATEADD(MONTH, @month, -1))
    END
    
    RETURN 'Total Revenue for ' + DATENAME(MONTH, DATEADD(MONTH, @month, -1)) + ': ' + CONVERT(VARCHAR, @sum) + ' ILS'
END
GO

--------------- Table-Valued Function: favoriteDress
-- Description: Displays dresses according to customer requirements (Date, Categories, Price).

-- 1. Helper Function: temp
ALTER FUNCTION temp(@kategory1 SMALLINT, @kategory2 SMALLINT, @kategory3 SMALLINT, @price SMALLINT) 
RETURNS @t TABLE (
    ktId SMALLINT, rowNumber SMALLINT, dressId SMALLINT, 
    dressName VARCHAR(50), dressPrice SMALLINT, arrivalStatus VARCHAR(20)
) AS
BEGIN
    -- If no categories are specified, return all dresses matching the price range
    IF (@kategory1 IS NULL AND @kategory2 IS NULL AND @kategory3 IS NULL) 
    BEGIN
        INSERT INTO @t
        SELECT [ktId], ROW_NUMBER() OVER(PARTITION BY [ktId] ORDER BY [dateCome] DESC),
               [dressId], [dressName], [dressPrice],
               CASE
                   WHEN DATEDIFF(MONTH, [dateCome], GETDATE()) < 2 THEN 'New Release'
                   WHEN DATEDIFF(MONTH, [dateCome], GETDATE()) BETWEEN 2 AND 4 THEN 'Trendy'
                   WHEN DATEDIFF(MONTH, [dateCome], GETDATE()) BETWEEN 4 AND 8 THEN 'Relatively New'
                   ELSE 'Previous Seasons'
               END
        FROM [dbo].[dresses] 
        WHERE [dressPrice] BETWEEN (@price - 1000) AND (@price + 1000)
    END
    ELSE
    BEGIN
        INSERT INTO @t
        SELECT [ktId], ROW_NUMBER() OVER(PARTITION BY [ktId] ORDER BY [dateCome] DESC),
               [dressId], [dressName], [dressPrice],
               CASE
                   WHEN DATEDIFF(MONTH, [dateCome], GETDATE()) < 2 THEN 'New Release'
                   WHEN DATEDIFF(MONTH, [dateCome], GETDATE()) BETWEEN 2 AND 4 THEN 'Trendy'
                   WHEN DATEDIFF(MONTH, [dateCome], GETDATE()) BETWEEN 4 AND 8 THEN 'Relatively New'
                   ELSE 'Previous Seasons'
               END
        FROM [dbo].[dresses] 
        WHERE ([ktId] IN (@kategory1, @kategory2, @kategory3)) 
          AND ([dressPrice] BETWEEN (@price - 1000) AND (@price + 1000))
    END
    RETURN 
END
GO

-- 2. Main Function: favoriteDress
ALTER FUNCTION [dbo].[favoriteDress](@date DATE, @kategory1 SMALLINT, @kategory2 SMALLINT, @kategory3 SMALLINT, @price SMALLINT) 
RETURNS @t TABLE (
    ktId SMALLINT, rowNumber SMALLINT, dressId SMALLINT, 
    dressName VARCHAR(50), dressPrice SMALLINT, arrivalStatus VARCHAR(20)
) AS
BEGIN
    -- Fetch potential dresses from helper function
    INSERT INTO @t
    SELECT * FROM dbo.temp(@kategory1, @kategory2, @kategory3, @price)

    -- Filter out dresses that are already booked or unavailable
    -- Criteria: Must be 15 days after previous event, and used no more than 3 times total.
    DELETE FROM @t WHERE dressId IN (
        SELECT [dbo].[dresses].[dressId]
        FROM [dbo].[BridesDetails] JOIN [dbo].[orders] 
        ON [dbo].[BridesDetails].[BrideId] = [dbo].[orders].[BrideId]
        JOIN [dbo].[dresses] ON [dbo].[dresses].[dressId] = [dbo].[orders].[dressId]
        WHERE @date < DATEADD(DAY, 15, [DateEven]) 
        OR [dbo].[orders].[dressId] IN (SELECT [dressId] FROM [dbo].[orders] GROUP BY [dressId] HAVING COUNT([dressId]) > 3)
    )
    RETURN
END
GO

-----------------------------------------------------------------------------------------
-- VIEW SECTION
-----------------------------------------------------------------------------------------

--- View: takenToday
--- Description: Monitors daily inventory movements.
--- 1. Displays dresses scheduled for pickup today.
--- 2. Displays dresses overdue for return (more than 1 day after the wedding).

CREATE VIEW [dbo].[takenToday] AS (
    SELECT b.[BrideId], [BrideName], [BridePhone], [DressId], 'Pickup' AS 'Action', [pay] AS 'IsPaid'
    FROM [dbo].[BridesDetails] b JOIN [dbo].[orders] o ON b.[BrideId] = o.[BrideId]
    JOIN (SELECT * FROM [dbo].[turns] WHERE [date] = CAST(GETDATE() AS DATE) AND [type] = 'Pickup') AS q1
    ON b.[BrideId] = q1.brideId 
    WHERE [DateTake] IS NULL 
    
    UNION
    
    SELECT b.[BrideId], [BrideName], [BridePhone], [DressId], 'Overdue Return' AS 'Action', [pay] AS 'IsPaid'
    FROM [dbo].[BridesDetails] b JOIN [dbo].[orders] o ON b.[BrideId] = o.[BrideId]
    WHERE DATEDIFF(DAY, [DateEven], GETDATE()) >= 1 AND [DateReturn] IS NULL
)
GO
