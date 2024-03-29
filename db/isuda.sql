CREATE TABLE entry (
    id BIGINT UNSIGNED AUTO_INCREMENT NOT NULL PRIMARY KEY,
    author_id BIGINT UNSIGNED NOT NULL,
    keyword VARCHAR(191) UNIQUE,
    description MEDIUMTEXT,
    updated_at DATETIME NOT NULL,
    created_at DATETIME NOT NULL
) Engine=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

CREATE TABLE user (
    id BIGINT UNSIGNED AUTO_INCREMENT NOT NULL PRIMARY KEY,
    name VARCHAR(191) UNIQUE,
    salt VARCHAR(20),
    password VARCHAR(40),
    created_at DATETIME NOT NULL
) Engine=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE spam (
    id BIGINT UNSIGNED AUTO_INCREMENT NOT NULL PRIMARY KEY,
    content_hash VARCHAR(100) NOT NULL UNIQUE,
    valid TINYINT NOT NULL
) Engine=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;
