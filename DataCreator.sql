create schema banking;

CREATE TABLE Bank (
  idBank INT PRIMARY KEY,
  Name VARCHAR(100),
  Captialization int
);

CREATE TABLE Branch (
  idBranch INT PRIMARY KEY,
  Address varchar(255),
  Bank_idBank int,
  foreign key (Bank_idBank) references Bank(idBank)
);

CREATE TABLE Client (
  idClient INT PRIMARY KEY,
  Name VARCHAR(50),
  Surname varchar(50),
  Branch_idBranch int,
  foreign key (Branch_idBranch) references Branch(idBranch)
);

CREATE TABLE Account (
  idAccount INT PRIMARY KEY,
  Balance INT,
  open_date date,
  Client_idClient int,
  foreign key (Client_idClient) references Client(idClient)
);

CREATE TABLE Loans (
  idLoan INT PRIMARY KEY,
  Amount INT,
  loan_date date,
  Account_idAccount int,
  foreign key (Account_idAccount) references Account(idAccount)
);


-- Inserting data into the Bank table
INSERT INTO Bank (idBank, Name, Captialization) VALUES
  (1, 'Absa', 1000000),
  (2, 'Nedbank', 500000),
  (3, 'FNB', 750000);

-- Inserting data into the Branch table
INSERT INTO Branch (idBranch, Address, Bank_idBank) VALUES
  (1, 'Address 1', 1),
  (2, 'Address 2', 1),
  (3, 'Address 3', 2),
  (4, 'Address 4', 3);

-- Inserting data into the Client table
INSERT INTO Client (idClient, Name, Surname, Branch_idBranch) VALUES
  (1, 'John', 'Doe', 1),
  (2, 'Jane', 'Smith', 2),
  (3, 'Michael', 'Johnson', 3),
  (4, 'Sarah', 'Williams', 4);

-- Inserting data into the Account table
INSERT INTO Account (idAccount, Balance, open_date, Client_idClient) VALUES
  (1, 5000, '2022-01-01', 1),
  (2, 10000, '2022-02-15', 2),
  (3, 7500, '2022-03-10', 3),
  (4, 12000, '2022-04-20', 4);

-- Inserting data into the Loans table
INSERT INTO Loans (idLoan, Amount, loan_date, Account_idAccount) VALUES
  (1, 2000, DATE_ADD('2023-03-01', INTERVAL FLOOR(RAND() * DATEDIFF('2023-06-30', '2023-03-01')) DAY), 1),
  (2, 5000, DATE_ADD('2023-03-01', INTERVAL FLOOR(RAND() * DATEDIFF('2023-06-30', '2023-03-01')) DAY), 2),
  (3, 10000,DATE_ADD('2023-03-01', INTERVAL FLOOR(RAND() * DATEDIFF('2023-06-30', '2023-03-01')) DAY), 3),
  (4, 3000, DATE_ADD('2023-03-01', INTERVAL FLOOR(RAND() * DATEDIFF('2023-06-30', '2023-03-01')) DAY), 4),
  (5, 3000, DATE_ADD('2023-03-01', INTERVAL FLOOR(RAND() * DATEDIFF('2023-06-30', '2023-03-01')) DAY), 1),
  (6, 6000, DATE_ADD('2023-03-01', INTERVAL FLOOR(RAND() * DATEDIFF('2023-06-30', '2023-03-01')) DAY), 2),
  (7, 11000, DATE_ADD('2023-03-01', INTERVAL FLOOR(RAND() * DATEDIFF('2023-06-30', '2023-03-01')) DAY), 3),
  (8, 4000,  DATE_ADD('2023-03-01', INTERVAL FLOOR(RAND() * DATEDIFF('2023-06-30', '2023-03-01')) DAY), 4),
  (9, 4000,  DATE_ADD('2023-03-01', INTERVAL FLOOR(RAND() * DATEDIFF('2023-06-30', '2023-03-01')) DAY), 1),
  (10, 7000,  DATE_ADD('2023-03-01', INTERVAL FLOOR(RAND() * DATEDIFF('2023-06-30', '2023-03-01')) DAY), 2),
  (11, 12000,  DATE_ADD('2023-03-01', INTERVAL FLOOR(RAND() * DATEDIFF('2023-06-30', '2023-03-01')) DAY), 3),
  (12, 5000,  DATE_ADD('2023-03-01', INTERVAL FLOOR(RAND() * DATEDIFF('2023-06-30', '2023-03-01')) DAY), 4),
  (13, 5000, DATE_ADD('2023-03-01', INTERVAL FLOOR(RAND() * DATEDIFF('2023-06-30', '2023-03-01')) DAY), 1),
  (14, 8000,  DATE_ADD('2023-03-01', INTERVAL FLOOR(RAND() * DATEDIFF('2023-06-30', '2023-03-01')) DAY), 2),
  (15, 13000,  DATE_ADD('2023-03-01', INTERVAL FLOOR(RAND() * DATEDIFF('2023-06-30', '2023-03-01')) DAY), 3),
  (16, 6000,  DATE_ADD('2023-03-01', INTERVAL FLOOR(RAND() * DATEDIFF('2023-06-30', '2023-03-01')) DAY), 4);