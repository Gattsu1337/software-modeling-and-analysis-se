CREATE DATABASE loyalist_db;
USE loyalist_db;

CREATE TABLE [User] (
	[user_id] INT IDENTITY(1,1) PRIMARY KEY,
	username VARCHAR(100) NOT NULL UNIQUE,
	[role] VARCHAR(20) DEFAULT 'viewer',
	email VARCHAR(255) NOT NULL UNIQUE,
	password_hash VARCHAR(255) NOT NULL
);

CREATE TABLE Post (
	post_id INT IDENTITY(1, 1) PRIMARY KEY,
	creator_id INT NOT NULL,
	caption NVARCHAR(MAX),
	created_at DATETIME DEFAULT GETDATE(),
	visibility VARCHAR(20) CHECK (visibility IN ('public', 'followers', 'subscribers')) DEFAULT 'subscribers',
	FOREIGN KEY (creator_id) REFERENCES [User](user_id) ON DELETE CASCADE
);

CREATE TABLE MediaFile (
	media_id INT IDENTITY(1,1) PRIMARY KEY,
	post_id INT NOT NULL,
	file_url NVARCHAR(500) NOT NULL,
	uploaded_at DATETIME DEFAULT GETDATE(),
	file_type VARCHAR(50),
	FOREIGN KEY (post_id) REFERENCES Post(post_id) ON DELETE CASCADE
);

CREATE TABLE Comment (
	comment_id INT IDENTITY(1,1) PRIMARY KEY,
	user_id INT NOT NULL,
	post_id INT NOT NULL,
	created_at DATETIME DEFAULT GETDATE(),
	text NVARCHAR(MAX) NOT NULL,
	FOREIGN KEY (user_id) REFERENCES [User](user_id),
	FOREIGN KEY (post_id) REFERENCES Post(post_id) ON DELETE CASCADE
);

CREATE TABLE [Like] (
	like_id INT IDENTITY(1,1) PRIMARY KEY,
	user_id INT NOT NULL,
	post_id INT NOT NULL,
	FOREIGN KEY (user_id) REFERENCES [User](user_id),
	FOREIGN KEY (post_id) REFERENCES [Post](post_id) ON DELETE CASCADE,
	CONSTRAINT UQ_Like UNIQUE (user_id, post_id)
);

CREATE TABLE Message (
	message_id INT IDENTITY(1,1) PRIMARY KEY,
	sender_id INT NOT NULL,
	receiver_id INT NOT NULL,
	text NVARCHAR(MAX) NOT NULL,
	sent_at DATETIME DEFAULT GETDATE(),
	read_status BIT DEFAULT 0,
	FOREIGN KEY (receiver_id) REFERENCES [User](user_id),
	FOREIGN KEY (sender_id) REFERENCES [User](user_id),
);

CREATE TABLE Subscription (
	subscription_id INT IDENTITY(1,1) PRIMARY KEY,
	viewer_id INT NOT NULL,
	creator_id INT NOT NULL,
	start_date DATETIME DEFAULT GETDATE(),
	auto_renewal BIT DEFAULT 1,
	price DECIMAL(10,2) DEFAULT 0.00,
	active_status BIT DEFAULT 1,
	FOREIGN KEY (viewer_id) REFERENCES [User](user_id),
	FOREIGN KEY (creator_id) REFERENCES [User](user_id),
	CONSTRAINT UQ_Subscription UNIQUE (viewer_id, creator_id),
);

CREATE TABLE Payment (
	payment_id INT IDENTITY(1,1) PRIMARY KEY,
	subscription_id INT NOT NULL,
	receiver_id INT NOT NULL,
	sender_id INT NOT NULL,
	payment_date DATETIME DEFAULT GETDATE(),
	amount DECIMAL(10,2) NOT NULL,
	status VARCHAR(20) CHECK (status in ('pending', 'completed', 'failed')) DEFAULT 'pending',
	FOREIGN KEY (subscription_id) REFERENCES Subscription(subscription_id) ON DELETE CASCADE,
	FOREIGN KEY (receiver_id) REFERENCES [User](user_id),
	FOREIGN KEY (sender_id) REFERENCES [User](user_id),
);


CREATE FUNCTION dbo.fn_GetPostCount (@UserId INT)
RETURNS INT
AS
BEGIN
	DECLARE @Count INT;
	SELECT @Count = COUNT(*) FROM Post WHERE creator_id = @UserId;
	RETURN @Count;
END;
GO

CREATE FUNCTION dbo.fn_GetTotalEarnings (@CreatorId INT)
RETURNS DECIMAL(10,2)
AS
BEGIN
	DECLARE @Total DECIMAL(10,2);
	SELECT @Total = ISNULL(SUM(amount), 0)
	FROM Payment
	WHERE receiver_id = @CreatorId AND status = 'completed';
	RETURN @Total;
END;
GO

CREATE PROCEDURE dbo.sp_AddPost
	@CreatorId INT,
	@Caption NVARCHAR(MAX),
	@Visibility VARCHAR(20),
	@FileUrl NVARCHAR(500) = NULL
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @PostId INT;

	INSERT INTO Post (creator_id, caption, visibility)
	VALUES (@CreatorId, @Caption, @Visibility);

	SET @PostId = SCOPE_IDENTITY();

	IF @FileUrl IS NOT NULL
	BEGIN 
		INSERT INTO MediaFile (post_id, file_url)
		VALUES(@PostId, @FileUrl);
	END

	SELECT @PostId AS NewPostId;
END;
GO

CREATE PROCEDURE dbo.sp_RecordPayment
	@SubscriptionId INT,
	@SenderId INT,
	@ReceiverId INT,
	@Amount DECIMAL(10,2)
AS
BEGIN
	SET NOCOUNT ON;

	INSERT INTO Payment (subscription_id, sender_id, receiver_id, amount, status)
	VALUES (@SubscriptionId, @SenderId, @ReceiverId, @Amount, 'completed');

	UPDATE Subscription
	SET active_status = 1, start_date = GETDATE()
	WHERE subscription_id = @SubscriptionId;
END;
GO

CREATE TABLE PostDeleteLog(
	log_id INT IDENTITY(1,1) PRIMARY KEY,
	post_id INT,
	deleted_at DATETIME DEFAULT GETDATE(),
	creator_id INT,
	caption NVARCHAR(MAX)
);

CREATE TRIGGER trg_LogDeletedPost 
ON Post
AFTER DELETE
AS
BEGIN
	INSERT INTO PostDeleteLog (post_id, creator_id, caption)
	SELECT post_id, creator_id, caption FROM deleted;
END;
GO

CREATE TRIGGER trg_PreventSelfSubscription 
ON Subscription
INSTEAD OF INSERT
AS
BEGIN
	IF EXISTS (SELECT * FROM inserted WHERE viewer_id = creator_id)
	BEGIN
		RAISERROR ('A user cannot subscribe to themselves.', 16, 1);
		ROLLBACK TRANSACTION;
		RETURN;
	END;

	INSERT INTO Subscription (viewer_id, creator_id, start_date, auto_renewal, price, active_status)
	SELECT viewer_id, creator_id, start_date, auto_renewal, price, active_status FROM inserted;
END;
GO

CREATE TRIGGER trg_PaymentCompleted
ON Payment
AFTER INSERT
AS 
BEGIN
	UPDATE [User]
	SET role = 'creator'
	WHERE user_id IN (SELECT receiver_id FROM inserted)
		AND role <> 'creator';
END;
GO