#!/bin/sh

(while read f; do
    diff -ub $f tmp/$f;
done) <<EOF
test0.mem
test1.mem
test2.mem
test3.mem
test4.mem
test5.mem
test6.mem
test7.mem
test8.mem
test9.mem
test10.mem
test11.mem
test12.mem
test13.mem
test14.mem
test15.mem
test16.mem
EOF