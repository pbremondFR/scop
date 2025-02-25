@echo OFF
odin build src -vet -warnings-as-errors -o:speed -disable-assert -out:scop.exe
