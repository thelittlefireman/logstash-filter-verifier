# Logstash Filter Verifier

The [Logstash](https://www.elastic.co/products/logstash) program for
collecting and processing logs from is popular and commonly used to
process e.g. syslog messages and HTTP logs.

Apart from ingesting log events and sending them to one or more
destinations it can transform the events in various ways, including
extracting discrete fields from flat blocks of text, joining multiple
physical lines into singular logical events, parsing JSON and XML, and
deleting unwanted events. It uses its own domain-specific
configuration language to describe both inputs, outputs, and the
filters that should be applied to events.

Writing the filter configurations necessary to parse events isn't
difficult for someone with basic programming skills, but verifying
that the filters do what you expect can be tedious; especially when
you tweak existing filters and want to make sure that all kinds of
logs will continue to be processed as before. If you get something
wrong you might have millions of incorrectly parsed events before you
realize your mistake.

This is where Logstash Filter Verifier comes in. In lets you define
test case files containing lines of input together with the expected
output from Logstash. Pass one of more such test case files to
Logstash Filter Verifier together with all of your Logstash filter
configuration files and it'll run Logstash for you and verify that
Logstash actually return what you expect.

Before you can run Logstash Filter Verifier you need to compile
it. After covering that, let's start with a simple example and follow
up with reference documentation.

## Building

This program is written in the [Go](https://golang.org/) language and
needs to be compiled before it can be run. Go compilers are available
for most platforms that Logstash runs on, including Windows. Many
Linux distributions make some version of the Go compiler easily
installable, but otherwise you can [download and install the latest
version](https://golang.org/dl/). You should be able to compile the
source code with any reasonable up to date version of the Go compiler.

To download and compile the source, run these commands (pick another
directory name if you like):

    $ mkdir ~/go
    $ cd ~/go
    $ export GOPATH=$(pwd)
    $ go get github.com/magnusbaeck/logstash-filter-verifier
    $ cd src/github.com/magnusbaeck/logstash-filter-verifier
    $ go get
    $ go build

If successful you'll find an executable in the current directory.

## Examples

The examples that follow build upon each other and do not only show
how to use Logstash Filter Verifier to test that particular kind of
log. They also highlight how to deal with different features in logs.

### Syslog messages

Logstash is often used to parse syslog messages, so let's use that as
a first example.

Test case files are in JSON format and contain a single object with
about a handful of supported properties.

```javascript
{
  "type": "syslog",
  "input": [
    "Oct  6 20:55:29 myhost myprogram[31993]: This is a test message"
  ],
  "expected": [
    {
      "@timestamp": "2015-10-06T20:55:29.000Z",
      "@version": "1",
      "host": "myhost",
      "message": "This is a test message",
      "pid": 31993,
      "program": "myprogram",
      "type": "syslog"
    }
  ]
}
```

In this example, `type` is set to "syslog" which means that the input
events in this test case will have that in their `type` field when
they're passed to Logstash. Next, in `input`, we define a single test
string that we want to feed through Logstash, and the `expected` array
contains a one-element object with the event we expect Logstash to
emit for the given input.

Note that UTC is the assumed timezone for input events to avoid
different behavior depending on the timezone of the machine where
Logstash Filter Verifier happens to run. This won't affect time
formats that include a timezone.

This command will run this test case file through
Logstash Filter Verifier (replace all "path/to" with the actual paths
to the files, obviously):

    $ path/to/logstash-filter-verifier path/to/syslog.json path/to/filters

If the test is successful, Logstash Filter Verifier will terminate
with a zero exit code and (almost) no output. If the test fails it'll
run `diff -u` to compare the pretty-printed JSON representation of the
expected and actual events.

### JSON messages

I always prefer to configure application to emit JSON objects
whenever possible so that I don't have to write complex and/or
ambiguous grok expressions. Here's an example:

```javascript
{"message": "This is a test message", "client": "127.0.0.1", "host": "myhost", "time": "2015-10-06T20:55:29Z"}
```

When you feed events like this to Logstash it's likely that the
input used will have its codec set to "json". This is something we
should mimic on the Logstash Filter Verifier side too. Use `codec` for
that:

```javascript
{
  "type": "app",
  "codec": "json",
  "input": [
    "{\"message\": \"This is a test message\", \"client\": \"127.0.0.1\", \"host\": \"myhost\", \"time\": \"2015-10-06T20:55:29Z\"}"
  ],
  "expected": [
    {
      "@timestamp": "2015-10-06T20:55:29.000Z",
      "@version": "1",
      "client": "localhost",
      "clientip": "127.0.0.1",
      "host": "myhost",
      "message": "This is a test message",
      "type": "app"
    }
  ]
}
```

There are a few points to be made here:

* The double quotes inside the string must be escaped.
* The filters being tested here use Logstash's [dns
  filter](https://www.elastic.co/guide/en/logstash/current/plugins-filters-dns.html)
  to transform the IP address in the "client" field into a hostname
  and copy the original IP address into the "clientip" field. To avoid
  future problems and flaky tests, pick a hostname or IP address for
  the test case that will always resolve to the same thing. As in this
  example, localhost and 127.0.0.1 should be safe picks.

## Test case file reference

Test case files are JSON files containing a single object. That object
may have the following properties:

* `codec`: A string value naming the Logstash codec that should be
  used when events are read. This is normally "plain" or "json".
* `expected`: An array of JSON objects with the events to be
  expected. They will be compared to the actual events produced by the
  Logstash process.
* `input`: An array with the lines of input (each line being a string)
  that should be fed to the Logstash process.
* `type`: A string value with the contents of the "type" field of the
  events that are to be read. This is often important since filters
  typically are configured based on the event's type.

## Known limitations and future work

* Some log formats don't include all timestamp components. For
  example, most syslog formats don't include the year. This should be
  dealt with somehow.
* JSON files are tedious to write for a human with brackets, braces,
  double quotes, and escaped double quotes everywhere and no native
  support for comments. We should support YAML in addition to JSON to
  make it more pleasant to write test case files.
* You can't add any field values to the input lines, except the
  type. We might as well support adding any fields.
* All Logstash processes are run serially. By running them in parallel
  the execution time can be reduced drastically on multi-core
  machines.
* Sometimes filters (or Logstash itself) add fields with dynamic
  values that can't be predicted beforehand and therefore can't be
  hardwired into the test case file. It should be possible to ignore
  such fields when comparing the events.

## License

This software is copyright 2015 by Magnus Bäck <<magnus@noun.se>>
and licensed under the Apache 2.0 license. See the LICENSE file for the full
license text.