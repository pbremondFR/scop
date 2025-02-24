# **************************************************************************** #
#                                                                              #
#                                                         :::      ::::::::    #
#    Makefile                                           :+:      :+:    :+:    #
#                                                     +:+ +:+         +:+      #
#    By: pbremond <pbremond@student.42nice.fr>      +#+  +:+       +#+         #
#                                                 +#+#+#+#+#+   +#+            #
#    Created: 2025/02/24 18:03:54 by pbremond          #+#    #+#              #
#    Updated: 2025/02/24 18:03:54 by pbremond         ###   ########.fr        #
#                                                                              #
# **************************************************************************** #

SRC_DIR = src
SRC = $(wildcard $(SRC_DIR)/*.odin)
TARGET = scop
TARGET_DEBUG = scop_debug

all: $(TARGET)

debug: $(TARGET_DEBUG)

$(TARGET): $(SRC)
	odin build $(SRC_DIR) -vet -warnings-as-errors -o:speed -disable-assert -out:$(TARGET)

$(TARGET_DEBUG): $(SRC)
	odin build $(SRC_DIR) -debug -out:$(TARGET_DEBUG)

fclean:
	rm $(TARGET)
