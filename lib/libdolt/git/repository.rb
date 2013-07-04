# encoding: utf-8
#--
#   Copyright (C) 2012-2013 Gitorious AS
#
#   This program is free software: you can redistribute it and/or modify
#   it under the terms of the GNU Affero General Public License as published by
#   the Free Software Foundation, either version 3 of the License, or
#   (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU Affero General Public License for more details.
#
#   You should have received a copy of the GNU Affero General Public License
#   along with this program.  If not, see <http://www.gnu.org/licenses/>.
#++
require "rugged"
require "libdolt/git"
require "libdolt/git/blame"
require "libdolt/git/commit"
require "libdolt/git/submodule"
require "libdolt/git/tree"

module Dolt
  module Git
    class Repository
      def initialize(root)
        @repo = Rugged::Repository.new(root)
      end

      def bare?; @repo.bare?; end
      def path; @repo.path; end
      def rev_parse(*args); @repo.rev_parse(*args); end
      def rev_parse_oid(*args); @repo.rev_parse_oid(*args); end
      def refs(*args); @repo.refs(*args); end
      def lookup(*args); @repo.lookup(*args); end

      def submodules(ref)
        config = rev_parse("#{ref}:.gitmodules")
        Dolt::Git::Submodule.parse_config(config.content)
      rescue Rugged::TreeError => err
        # Raised if .gitmodules cannot be found, which means no submodules
        []
      end

      def blob(ref, path)
        rev_parse("#{ref}:#{path}")
      end

      def tree(ref, path)
        object = rev_parse("#{ref}:#{path}")
        raise StandardError.new("Not a tree") if !object.is_a?(Rugged::Tree)
        annotate_tree(ref, path, object)
      end

      def tree_entry(ref, path)
        annotate_tree(ref, path, rev_parse("#{ref}:#{path}"))
      end

      def blame(ref, blob_path)
        process = Dolt::Git.git(path, "blame -l -t -p #{ref} -- #{blob_path}")
        Dolt::Git::Blame.parse_porcelain(process.stdout.read)
      end

      def log(ref, path, limit)
        entry_history(ref, path, limit)
      end

      def tree_history(ref, path, limit = 1)
        tree = rev_parse("#{ref}:#{path}")

        if tree.class != Rugged::Tree
          message = "#{ref}:#{path} is not a tree (#{tree.class.to_s})"
          raise Exception.new(message)
        end

        annotate_history(path || "./", ref, tree, limit)
      end

      def readmes(ref, path="")
        tree(ref, path).entries.select do |e|
          e[:type] == :blob && e[:name].match(/readme/i)
        end
      rescue Exception => err
        []
      end

      private
      def entry_history(ref, entry, limit)
        process = Dolt::Git.git(path, "log -n #{limit} #{ref} -- #{entry}")
        Dolt::Git::Commit.parse_log(process.stdout.read)
      end

      def annotate_history(path, ref, entries, limit)
        resolve = lambda { |p| path == "" ? p : File.join(path, p) }
        entries.map do |e|
          e.merge(:history => entry_history(ref, resolve.call(e[:name]), limit))
        end
      end

      def annotate_tree(ref, path, object)
        if object.class.to_s.match(/Blob/) || !object.find { |e| e[:type].nil? }
          return object
        end

        annotate_submodules(ref, path, object)
      end

      def annotate_submodules(ref, path, tree)
        modules = submodules(ref)

        entries = tree.entries.map do |entry|
          if entry[:type].nil?
            mod = path == "" ? entry[:name] : File.join(path, entry[:name])
            meta = modules.find { |s| s[:path] == mod }
            if meta
              entry[:type] = :submodule
              entry[:url] = meta[:url]
            end
          end
          entry
        end

        Dolt::Git::Tree.new(tree.oid, entries)
      end
    end
  end
end
