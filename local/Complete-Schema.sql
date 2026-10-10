USE [GameDB];
GO
-- Equivalent to the guild bootstrap, without DELETE or duplicate-column errors.
IF COL_LENGTH('dbo.guild', 'banklog') IS NULL
    ALTER TABLE dbo.guild ADD banklog varchar(8000) NOT NULL DEFAULT ('');
GO
DECLARE @id int = 0;
WHILE @id < 199
BEGIN
    IF NOT EXISTS (SELECT 1 FROM dbo.guild WHERE guild_id=@id)
        INSERT dbo.guild (guild_id,guild_name) VALUES (@id,'Pirate Guild '+CONVERT(varchar(3),@id));
    SET @id += 1;
END;
GO
