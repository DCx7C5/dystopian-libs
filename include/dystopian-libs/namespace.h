//
// Created by daen on 19.09.25.
//

#ifndef DYSTOPIAN_LIBS_NAMESPACE_H
#define DYSTOPIAN_LIBS_NAMESPACE_H

// Define primary namespace for the entire project
#define DYSTOPIAN_NAMESPACE namespace dystopian
#define DYSTOPIAN_NAMESPACE_BEGIN DYSTOPIAN_NAMESPACE {
#define DYSTOPIAN_NAMESPACE_END }

// Define application level namespace
#define DL_NAMESPACE DYSTOPIAN_NAMESPACE::libs
#define DL_NAMESPACE_BEGIN DL_NAMESPACE {
#define DL_NAMESPACE_END }

// Define application level namespace
#define DL_BASE_NAMESPACE DYSTOPIAN_NAMESPACE::base
#define DL_BASE_NAMESPACE_BEGIN DL_BASE_NAMESPACE {
#define DL_BASE_NAMESPACE_END }


// First declare the actual namespaces
namespace dystopian::libs::base {}

// Then create the namespace aliases
namespace dl = dystopian::libs;
namespace dbase = dystopian::libs::base;

#endif //DYSTOPIAN_LIBS_NAMESPACE_H