#!/usr/bin/env perl
use strict;
use warnings;
use Data::Dumper;
sub DUMP(@) { Dumper(@_) }
sub D(@){ print DUMP(@_) }
 $|++;
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

die qq{$action is not a known action\n} unless $hub->can($action);
$hub->$action(@ARGV);


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
require LWP::Simple; 

use constant RW_STR => qw{is rw isa Str}; # PLEASE DO NOT EVER DO THIS, I'm lazy and this is a hack.

has host     => RW_STR, default => 'http://github.com/api/v2/json';
has username => RW_STR, predicate => 'has_username'; 
has repos    => 
  is => 'rw',
  isa => 'HashRef',
  lazy => 1,
  default => sub{
    my $self = shift;
    #{ watched => $self->get(qw{repos watched}, $self->username)->{repositories},
    #  show    => $self->get(qw{repos show   }, $self->username)->{repositories},
    #}
    my $out = {};
    foreach my $repo ( @{ $self->get(qw{repos watched}, $self->username)->{repositories} } ,
                       @{ $self->get(qw{repos show},    $self->username)->{repositories} } # this is paged to 30 items, set up pagination 
                     ) {
      my $type = $repo->{fork}                       ? 'fork'
               : $repo->{owner} ne $self->{username} ? 'watched'
               :                                       'standard' ; 
      push @{$out->{$type}}, $repo;
      $out->{by_name}->{$repo->{name}}->{$repo->{url}} = $repo; # we want only unique URL's so build a hash
    }
    $out->{by_name} = { map{ $_ => [values %{$out->{by_name}->{$_}}] } keys %{$out->{by_name}} }; # because I don't care about the keys just the unique values, lets back out of the url as a key
    $out;
  }
;

sub mkurl { join '/', shift->host, @_; } 
sub get   { # can not use 'around' due to get being a function
  my $url = shift->mkurl(@_);
  my $ret;
  eval { $ret = LWP::Simple::get( $url );
         from_json( $ret );
       } or do { die sprintf q{ERROR: %s did not return valid JSON, got %s instead.}, $url, $ret };
}
sub show  {
  my $self = shift;
  my $user = shift;
  die 'A username is require to be passed to show' unless $user;
  $self->username($user) unless $self->has_username; # this is a catch to allow replicate and others to pass a username and not 'set it' when they loop
  if (@_) {
    [ map{ my $R = $self->repos->{by_name}->{$_}; # this is going to be an arrayref (we deref below)
           map{ $self->get(qw{repos show}, $_->{owner}, $_->{name})->{repository} } @$R
         } @_
    ];
  }
  else {
    $self->repos;
  }
}

sub clone {
  my $self = shift;
  my $user = shift;
 
  sub urlarize {
    my ($mine, $url) = @_;
    $mine ? sprintf q{git@github.com:%s}, $url =~ m{github\.com/(.*)$}
          : sprintf q{git://%s}         , $url =~ m{://(.*)$}
    ;
  }
 
  foreach my $name (@_) {
    foreach my $repo ( @{ $self->show($user => $name) } ) {
      if (-d $repo->{name} ) {
        warn sprintf qq{%s already exists, skipping\n}, $repo->{name};
        next;
      }
      my $cmd = sprintf q{git clone %s}, urlarize($repo->{owner} eq $self->username, $repo->{url});
      $cmd .= sprintf q{ && cd %s && git remote add upstream %s && cd ..}, $repo->{name}, $repo->{parent}
           if exists $repo->{parent};
      
      #D {CMD => $cmd};
      qx{$cmd};
    }
  }
}  

sub replicate { # effectivly clone-all
  my $self = shift;
  my $user = shift;
  map{printf qq{[%s]\n}, $_->{name};
      $self->clone($_->{owner} => $_->{name}); # 3: clone that repo
      sleep(1)                                 # 4: be kind to the github
     }                                         
   map{@$_}                                    # 2: deref the value
   values %{ $self->show($user)->{by_name} };  # 1: use show to get all the repos that this user has access to (including watched)
}

sub refurb { # for all sub-dirs check and see if they are git repos and then 'update' by --fetch all and --reset hard
  my $self = shift;
  $|++;
  foreach my $git ( map{$_ =~ m{(.*)/\.git}
                       } qx{find . -maxdepth 2 -mindepth 1 -type d -name .git} # file find is stupid and will always recurse even when I don't want it to... 
                  ) {
    print qx{ echo '[$git]' && cd $git && git fetch --all && git reset --hard && cd ..};
  }
} 

}; # END


