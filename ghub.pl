#!/usr/bin/env perl
use strict;
use warnings;

=head1 USEAGE

  ghub.pl clone username/repo

=cut

sub help { die qx{perldoc $0} }

# print out our docs if we have not been given any args
help() unless @ARGV;

# do some simple setup
my $hub = My::GitHub->new;
my $action = shift @ARGV;
help() if $action eq 'help';

die qq{$action is not a known action} unless $hub->can($action);
print $hub->$action(@ARGV);


#------------------------------------------------
# Our Object 
#------------------------------------------------

BEGIN {
package My::GitHub;
use Data::Dumper;
sub DUMP(@) { Dumper(@_) }
sub D(@){ print DUMP(@_) }

use Mouse;
use JSON;
require LWP::Simple; # we'll implement our own get

has host => 
  is => 'rw',
  isa => 'Str',
  default => 'http://github.com/api/v2/json',
;

sub mkurl {
  join '/', shift->host, @_;
} 

sub get {
  my $self = shift;
  my $data = from_json( LWP::Simple::get( $self->mkurl(@_) ) )
}

sub repos {
  my $self = shift;
  my $view = shift;
  return {repositories => [@{$self->repos(show=>@_)->{repositories}},@{$self->repos(watched=>@_)->{repositories}}]}
      if $view eq 'all';
  die qq{Unknown view type of $view, given to repos. Accepted values are 'show', 'watched', and 'all'.} unless $view =~ m/^(?:show|watched)$/;
  shift->get('repos', $view,  @_);
}

sub show {
  print join qq{\n} 
      , map{ sprintf qq{%s %s %s}
                   , $_->{fork} eq 'true' ? 'F' : ' '
                   , $_->{url}
                   , $_->{description}
           } @{shift->repos( all => @_)->{repositories}}
}
  

}; # END


