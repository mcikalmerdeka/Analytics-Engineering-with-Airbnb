import pkg_resources

with open("requirements.txt") as f:
    packages = f.read().splitlines()

for package in packages:
    try:
        version = pkg_resources.get_distribution(package).version
        print(f"{package}=={version}")
    except pkg_resources.DistributionNotFound:
        print(f"{package} is not installed")