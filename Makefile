# Setup of the Python environment. Requires: make, uv, pip (and git, internet access).
# Run on the login node (SLURM jobs have no internet). Usage:
#   make venv     create .venv, clone gcages (main) and install everything
#   make update   git pull gcages and reinstall
#   make freeze   write the installed package list to ctemp/python_requirements_freeze.txt
#   make clean    remove .venv (the gcages clone is kept)

VENV        ?= .venv
PYTHON      ?= 3.11
GCAGES_URL  ?= https://github.com/openscm/gcages.git
GCAGES_DIR  ?= gcages
KERNEL_NAME ?= esm2025-sow
VPY          = $(VENV)/bin/python

.PHONY: venv update freeze clean

venv: $(VENV)/.installed

$(VENV)/.installed: requirements.txt
	# Fresh clone of gcages (main branch), kept outside git tracking
	[ -d $(GCAGES_DIR) ] || git clone $(GCAGES_URL) $(GCAGES_DIR)
	grep -qxF '$(GCAGES_DIR)/' .git/info/exclude 2>/dev/null || echo '$(GCAGES_DIR)/' >> .git/info/exclude
	grep -qxF '$(VENV)/' .git/info/exclude 2>/dev/null || echo '$(VENV)/' >> .git/info/exclude
	uv venv --python $(PYTHON) $(VENV)
	# One resolver call so the xarray pin in requirements.txt is respected by gcages' dependencies
	uv pip install -p $(VPY) -r requirements.txt -e "./$(GCAGES_DIR)[full]"
	# Jupyter kernel (written to ~/.local/share/jupyter/kernels)
	$(VPY) -m ipykernel install --user --name $(KERNEL_NAME) --display-name "$(KERNEL_NAME)"
	touch $@

update:
	git -C $(GCAGES_DIR) pull
	uv pip install -p $(VPY) -r requirements.txt -e "./$(GCAGES_DIR)[full]"

freeze:
	mkdir -p ctemp
	uv pip freeze -p $(VPY) > ctemp/python_requirements_freeze.txt

clean:
	rm -rf $(VENV)
