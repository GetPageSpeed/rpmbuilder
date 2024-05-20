Name:           hello
Version:        1.0
Release:        1%{?dist}
Summary:        Simple Hello World C Program

License:        MIT
URL:            http://example.com

Source0:        hello.c

BuildRequires:  gcc

%description
This is a simple "Hello, World!" C program for testing RPM builds.


%prep
cp %{SOURCE0} .


%build
gcc -o hello hello.c


%install
# Appears that %%{buildroot} is somehow misaligned as of Fedora 41,
# so using $RPM_BUILD_ROOT instead.
install -D -m 755 hello "$RPM_BUILD_ROOT%{_bindir}/%{name}"


%check
./hello > output.txt
echo "Hello, World!" > expected_output.txt
diff output.txt expected_output.txt


%files
%{_bindir}/%{name}


%changelog
* Wed Sep 20 2023 Your Name <you@example.com> - 1.0-1
- Initial package
